---
name: finance-tracker
description: Personal finance manager — track spending, set budgets, get financial advice.
---

# Finance Tracker

Use the `finance` command to manage personal finances. The data is stored in SQLite on the device.

## Commands

### Log a transaction
When the user says they spent money (e.g. "spent 350 on lunch", "paid 1500 for transport"), run:
```
finance spend <category> <amount> [note]
```
Categories: food, housing, transport, education, health, entertainment, shopping, travel, phone, misc

### Set a monthly budget
When the user says "budget food 6000" or "set a budget":
```
finance budget <category> <amount>
```

### Calculate monthly from total budget
When the user gives a total sum for a period (e.g. "7500 for 10 months"):
1. Divide total by months to get the monthly figure
2. Propose a category split that adds up to the monthly total
3. Set each category with `finance budget <category> <amount>`
4. Confirm the total matches: sum of category budgets = monthly figure
5. If the user corrects a category (e.g. "housing is 300 not 100"), recalculate the others to still fit within the monthly total
6. Run `finance budgets` to verify all categories are set

Example categories for DZD/local-currency context: food, housing, transport, education, health, phone, misc

### Check finances
When the user asks "report", "how did I spend", "monthly summary":
```
finance report [month]
```
If no month given, shows current month.

When the user asks "history", "recent transactions", "what did I spend":
```
finance history [category]
```

### Financial advice
When the user asks "can I afford X", "should I buy Y", "is this a good idea":
```
finance advise <amount> [category]
```
This checks budgets and remaining funds and gives advice. Always run this when the user asks about affordability.

## Behavior rules

- Always confirm after logging a transaction: "Logged: X — Y remaining this month".
- If the user mentions a cost without specifying a category, ask which category it falls under.
- When giving advice, be honest but supportive. If they can't afford something, suggest alternatives or提醒 them to wait.
- Never make up transactions — only log what the user explicitly tells you.
- The user can ask "budgets" to see all budgets.
- The user can ask "categories" to list available categories.
