# Phone Server

A Redmi Note 8 Pro (begonia) running Droidian, transformed into a 24/7 headless home server.

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
                    │  │ Caddy    │  │ Hermes   │  │
                    │  │ Portfolio│  │ WhatsApp │  │
                    │  └──────────┘  │ Gateway  │  │
                    │                └──────────┘  │
                    │  ┌──────────────────────────┐│
                    │  │ Finance Tracker (SQLite) ││
                    │  └──────────────────────────┘│
                    └──────────────────────────────┘
```

## Features

- **Portfolio site** — Next.js static site served by Caddy on port 8080
- **AI Assistant** — Hermes Agent with DeepSeek V4 Flash via WhatsApp
- **Finance Manager** — Budget tracking and financial advice via WhatsApp
- **Cloudflare Tunnel** — Public access without opening ports
- **Charge Limiter** — Battery kept at 45-50% for 24/7 plug-in
- **Self-Healing** — Auto-reconnect WiFi, restart crashed services, health checks every 5 min
- **USB Failover** — Static IP `192.168.42.1` when plugged via USB (RNDIS)

## Hardware

| Component | Detail |
|---|---|
| Phone | Redmi Note 8 Pro (begonia) |
| OS | Droidian (Debian-based) |
| Kernel | 4.14-141-xiaomi-begonia |
| WiFi | 2.4GHz (static IP `192.168.1.100`) |
| USB | RNDIS gadget (static IP `192.168.42.1`) |

## Software Stack

| Service | Role |
|---|---|
| **Caddy** | Web server for portfolio |
| **cloudflared** | Cloudflare Tunnel daemon |
| **Hermes Agent** | AI assistant with WhatsApp gateway |
| **SQLite** | Finance tracker database |
| **systemd** | Service management & auto-restart |

## Setup Files

- `caddy/Caddyfile` — Caddy web server config
- `cloudflared/config.yml` — Tunnel ingress rules
- `systemd/*.service` — Systemd service units
- `hermes/skills/finance/SKILL.md` — Finance tracker skill
- `bin/finance` — Finance tracker CLI

## Quick Reference

### Connect
```bash
ssh droidian@192.168.1.100   # WiFi (same router)
ssh droidian@192.168.42.1    # USB cable (any network)
```

### Manage services
```bash
sudo systemctl status caddy cloudflared hermes-gateway
sudo systemctl restart caddy cloudflared hermes-gateway
```

### Finance commands (via WhatsApp or SSH)
```
spent 350 on lunch           → logs expense
budget food 6000             → sets monthly budget
report                       → monthly summary
can I afford 5000?           → financial advice
history                      → recent transactions
```

### Check logs
```bash
journalctl -u hermes-gateway -n 50 --no-pager
journalctl -u caddy -n 50 --no-pager
```

## License

MIT
