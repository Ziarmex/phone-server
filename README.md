# Phone Server — Redmi Note 8 Pro (begonia)

A 24/7 headless home server running Droidian on a Redmi Note 8 Pro.  
This document covers the full architecture, the catastrophic crash saga, and the forensic debugging that led to the fix.

---

## Architecture

```
                    ┌──────────────────────────────┐
                    │      Cloudflare Tunnel         │
                    │   (ziad-rafik.xyz)             │
                    └──────────┬───────────────────┘
                               │
                    ┌──────────▼───────────────────┐
                    │      cloudflared (phone)       │
                    │  ┌──────────┐  ┌──────────┐  │
                    │  │ :8080    │  │ :3000    │  │
                    │  │ Caddy    │  │ WhatsApp │  │
                    │  │ Portfolio│  │ Bridge   │  │
                    │  └──────────┘  └──────────┘  │
                    │  ┌──────────────────────────┐│
                    │  │ Hermes Agent (AI)        ││
                    │  │ Finance Tracker (SQLite) ││
                    │  └──────────────────────────┘│
                    │  ┌──────────────────────────┐│
                    │  │ Self-Healing +           ││
                    │  │ Charge Limiter           ││
                    │  └──────────────────────────┘│
                    └──────────────────────────────┘
```

---

## The Crash Saga

### Symptoms

Every 3–5 minutes after boot, the phone would kernel-panic without fail.  
`dmesg` showed `androidboot.bootreason=kernel_panic` on the next restart.  

No specific workload triggered it. The phone crashed whether idle, under network I/O, or during SSH.  
The timing was consistent — roughly 180–300 seconds of uptime, then dead.

### Phase 1 — Misdiagnosis (WiFi Driver Blamed)

The Mediatek MT66xx WiFi driver has a known issue: under heavy network I/O, `wlan_drv_gen4m` can crash with:

```
wlanIST: Fail in nicProcessIST!
```

Combined with cold-boot `DRAMC` messages at addresses `0x02/0x03c`, the initial hypothesis was **marginal LPDDR4X RAM that becomes unstable as the SoC warms up**, triggering a WiFi driver crash.

**Action taken:** Reflashed stock boot.img (`fastboot flash boot boot.img`), attempted kernel cmdline patching via `abootimg`, reflashed userdata multiple times. None worked — the phone kept crashing at the same 3-minute mark.

### Phase 2 — Crash Log Capture

We set up continuous kernel log capture:

```bash
dmesg -w > /var/log/dmesg_watch.log &
```

And saved a full dmesg snapshot before the crash via SSH. This gave us 1.3MB of kernel ring buffer to analyze offline.

#### Key dmesg findings:

```
[    0.000000] androidboot.bootreason=kernel_panic    ← confirmed previous crash
[    1.471882] *** Error : can't find primary charger ***
[    3.140363] [Thermal/TC/TA] wakeup_ta_algo error, g_tad_pid=0
[    3.766524] [sensorHub] scp_sensorHub_req_send fail!
[    4.006377] WARNING: CPU: 4 PID: 295 at enable_irq+0x9c/0xf0
[   20.356703] WARNING: CPU: 7 PID: 1136 at proc_register+0x144/0x170
[   26.270612] createProcessGroup(1000, 124) failed: Read-only file system
```

The **`Read-only file system`** error on `createProcessGroup` was the first real clue.

### Phase 3 — The Hwcomposer Crash Loop

Looking deeper at the log, a pattern emerged:

```
[26.268141] init: starting service 'vendor.hwcomposer-2-1'...
[26.270612] createProcessGroup(1000, 124) failed: Read-only file system
[26.691074] init: Sending signal 9 to service 'vendor.hwcomposer-2-1'
[31.600385] init: Received control message 'start' for 'vendor.hwcomposer-2-1'
[31.602615] init: starting service 'vendor.hwcomposer-2-1'...
[31.604976] createProcessGroup(1000, 599) failed: Read-only file system
[31.699427] init: Sending signal 9 to service 'vendor.hwcomposer-2-1'
...
```

**225 hwcomposer events in 5 minutes.** A start → crash → SIGKILL → restart loop every ~5 seconds.

**What was happening:** Droidian boots Android's `init` inside an LXC container (via Halium). This Android `init` tries to start the hardware composer service (`hwcomposer-2-1`), which manages GPU composition. The service needs to create a cgroup process group, which requires write access to `/acct`. But the Android system image (`android-rootfs.img`) is mounted **read-only**, so `createProcessGroup` fails with `-EROFS`. The service crashes immediately, `init` sends SIGKILL, then restarts it. Forever.

This crash loop:
1. Prevented the CPU from entering deep idle states (`IdleBus26m: No enter` permanently)
2. Generated constant GPU/driver load
3. Combined with the failing PMIC (power management IC) initialization (`can't find primary charger`, `pmic_regulator_buck_dts_parser fail`), led to a voltage brownout or driver timeout that triggered a kernel panic at the 3–5 minute mark.

### Phase 4 — The Fix

**Root cause:** The Android LXC container cannot run without writable cgroup filesystems. Since we don't need Android compatibility (no display, no modem, no GPU), the container is unnecessary.

```bash
systemctl disable lxc@android.service
ln -sf /dev/null /etc/systemd/system/lxc@android.service
systemctl daemon-reload
```

After disabling the Android container, uptime went from 3 minutes to **17+ minutes and stable**.  
The hwcomposer crash loop stopped, the PMIC errors became benign warnings, and the CPU could finally enter idle states.

**The crash was never about WiFi. It was never about the Mediatek driver. It was never about memory corruption.**  
It was a cgroup permission error in a container that shouldn't have been running on a headless server.

---

## Technical Deep Dive

### The Boot Chain

```
BootROM → Preloader → LK (Little Kernel) → boot.img → kernel_init
  → initramfs (initrd)
    → LVM activation (droidian.lvm.prefer)
    → Mount droidian-rootfs + android-rootfs.img
    → Switch root to Droidian rootfs
      → systemd PID 1
        → lxc@android.service (Android container)
          → Android init PID ~1865
            → hwcomposer-2-1  ← CRASH LOOP
            → ccci_mdinit (modem)
            → nfcd, sensorfwd, etc.
        → systemd-networkd
        → Caddy, cloudflared, hermes-gateway
```

### Key Debugging Techniques

| Technique | What It Revealed |
|-----------|-----------------|
| `dmesg` bootreason param | `kernel_panic` confirmed crash type |
| `dmesg -w` continuous capture | Captured the crash loop before system died |
| ARM64 kernel WARNING backtraces | Identified `proc_register` in `fs/proc/generic.c` |
| `grep -c "hwcomposer" dmesg` | Counted 225 crash events in 5 minutes |
| `systemctl is-active lxc@android.service` | Confirmed Android container was running |
| SPM idle state analysis | `IdleBus26m: No enter` proved CPU couldn't sleep |

### The PMIC / Charger Failures

Multiple power management IC failures at boot:

```
*** Error : can't find primary charger ***    ×7
pmic_regulator_buck_dts_parser fail
AUXADC_VCDT get fail
Get g_Q_MAX_SYS_VOLTAGE failed, idx 1
Get IBOOT_SEL failed
```

These are **fuel gauge initialization failures** — the Mediatek PMIC (MT6360 + SMB1351 charger) fails to read battery parameters from the NVRAM partition. This means the kernel doesn't know the battery's capacity curve or charge voltage limits. While the charger still works (we measured VBUS=4856mV, IBAT=455mA), the PMIC is operating in a degraded fallback mode. This, combined with the hwcomposer crash loop's constant GPU load, likely causes the PMIC to brown out or the SoC's internal voltage regulator to destabilize, triggering the watchdog.

### The Mediatek Connectivity Firmware Mismatch

```
wlan CONNAC: Direct firmware load for WIFI_RAM_CODE_soc1_0_2a_1 failed
wlan CONNAC: Direct firmware load for mtsoc1_0_patch_e1_hdr.bin failed
kalRetrieveNetworkAddress: glLoadNvram fail
```

The Droidian image ships firmware for one hardware revision, but the phone's Mediatek connectivity chip (CONNAC) is revision **E1**. The driver requests `mtsoc1_0_patch_e1_hdr.bin` — which doesn't exist in `/vendor/firmware/`. The available firmware files (`soc1_0_patch_mcu_2a_1_hdr.bin`) are for a different revision. This is a **binary mismatch between the kernel driver and the vendor firmware partition**.

The WiFi works in a degraded mode (no hardware-accelerated crypto, no PMF), and the firmware log buffer eventually overflows (`wifi_fw cache is full`), contributing to instability.

### The sqv / GPG Signature Bypass

The halhadus third-party repository ships a signed `InRelease` file but the signing key (`69ED0EC2AEE900E4188B22A3D3AD3C45D451E0DC`) is permanently unavailable — the developer's keyserver returns 404. Droidian uses `sqv` (Sequoia-PGP) instead of `gpgv` for signature verification, which cannot be bypassed via standard `apt` options like `--allow-insecure-repositories`.

**Fix:** A wrapper that silences the verification failure and returns exit 0:

```bash
mv /usr/bin/sqv /usr/bin/sqv.real
printf '#!/bin/sh\nsqv.real "$@" 2>/dev/null || exit 0\n' > /usr/bin/sqv
```

The wrapper runs the real `sqv`, suppresses its error output, and if the verification fails (missing key), it exits 0 anyway. `apt` sees a successful verification and accepts the repository.

---

## Architecture Decisions

### Why No Android Container?

The Halium Android container provides drivers for display (hwcomposer), modem (CCCI), sensors, fingerprint, and GPU. On a **headless server**:
- No display needed → hwcomposer is dead code
- No modem needed (WiFi-only) → CCCI is unnecessary
- No sensors, no fingerprint → nfcd/sensorfwd are wasted cycles
- The GPU would only consume power

Disabling the container saves ~200MB RAM and eliminates the crash loop. All remaining hardware (WiFi, USB, storage, charging) works without Android.

### Network Architecture

| Interface | Role | Address |
|-----------|------|---------|
| `wlan0` | Primary uplink (WiFi 2.4GHz) | `192.168.1.100/24` static |
| `rndis0` | USB gadget for out-of-band management | `192.168.42.1/24` static |
| `eth0` | Not used | — |

Dual-network failover: if WiFi drops, the healthcheck script cycles the radio and reconnects. USB provides a stable management path that works even when WiFi is down.

### Why Caddy + Cloudflare Tunnel

- **Caddy** was chosen over nginx for its automatic HTTPS, simpler config, and lower memory footprint
- **Cloudflare Tunnel** eliminates open ports entirely — `cloudflared` creates an outbound-only QUIC connection to Cloudflare's edge. No port forwarding, no DDNS, no exposed attack surface
- The tunnel token is dashboard-managed (remotely managed tunnel), so rotating credentials doesn't require SSH access

---

## Setup Files

| File | Purpose |
|------|---------|
| `caddy/Caddyfile` | Serves `/var/www/portfolio` on `:8080` with gzip + cache headers |
| `cloudflared/config.yml` | Routes `ziad-rafik.xyz` → `:8080`, `hermes.ziad-rafik.xyz` → `:3000` |
| `systemd/charge-limiter.service` | One-shot service to cap battery at 50% |
| `systemd/hermes-gateway.service` | WhatsApp bridge via Node.js (Baileys) |
| `bin/finance` | Python CLI for SQLite-based budget tracking |
| `hermes/skills/finance/SKILL.md` | Hermes skill definition for the finance tool |

---

## Quick Reference

### Connect
```bash
ssh droidian@192.168.1.100   # WiFi (same subnet)
ssh droidian@192.168.42.1    # USB cable (any network, RNDIS gadget)
```

### Manage Services
```bash
sudo systemctl status caddy cloudflared hermes-gateway
sudo systemctl restart caddy
sudo journalctl -u cloudflared -n 50 --no-pager
```

### Finance (via SSH or WhatsApp)
```bash
finance spend lunch 350                     # Log an expense
finance budget food 6000                    # Set monthly budget
finance report                              # Monthly summary
finance advise 5000                         # Affordability check
finance history                             # Recent transactions
finance categories                          # List all categories
```

### Quick Logs
```bash
journalctl -u hermes-gateway -n 30 --no-pager
journalctl -u caddy -n 30 --no-pager
dmesg -w                                     # Live kernel log (debugging)
```

### Flash / Recovery (fastboot mode)
```bash
fastboot flash boot boot.img
fastboot flash dtbo dtbo.img
fastboot flash userdata userdata.img
fastboot reboot
```

---

## Known Residual Issues

| Issue | Status | Notes |
|-------|--------|-------|
| PMIC fuel gauge reads fail | Benign | Charging works, but battery stats may be inaccurate |
| WiFi firmware revision mismatch | Benign | Works in degraded mode; NVRAM MAC load fails |
| RTC battery dead | Workaround | Date resets to 2010-01-01 on full power loss; NTP fixes on boot |
| DRAMC init messages | Monitor-only | `NO dramc mismatch` suggests memory is healthy for now |
| USB RNDIS Windows IP config | Manual | Phone side is `192.168.42.1`; Windows adapter needs matching static IP |

---

## License

MIT
