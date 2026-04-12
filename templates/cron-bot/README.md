# cron-bot project template

A starter template for cron bots, data pipelines, and background workers.

## What this template is for

Use this template when your project:
- Runs on a schedule (cron, queue consumer, event-driven worker)
- Has no user-facing UI
- Processes data, syncs records, or executes automated strategies
- Needs audit trails, rollback capability, and backtest validation

Do NOT use this template for web apps, APIs, or anything with a browser UI — use the base `templates/CLAUDE.md.tmpl` instead.

## How it differs from the web-app template

| Concern | Web-app template | Cron-bot template |
|---------|-----------------|-------------------|
| UI / Playwright | Yes | No |
| Backtest harness | No | Yes |
| Rollback script | No | Yes |
| Health check | No | Yes |
| Audit log rules | No | Yes |
| Idempotency rules | No | Yes |

## Files

| File | Purpose |
|------|---------|
| `CLAUDE.md.tmpl` | CLAUDE.md template for the bot project. Fill in `{{SERVICE_NAME}}`, `{{MISSION}}`, `{{TECH_STACK}}`, `{{TEAM_TABLE}}`. |
| `scripts/backtest.sh` | Run a backtest over a date range. Takes `FROM_DATE TO_DATE CONFIG_FILE`, saves results to `.omc/experiments/`. |
| `scripts/rollback.sh` | Roll back to a previous git-tagged deployment. Confirms the tag exists, runs rollback steps (placeholder), appends to `.omc/audit/rollbacks.jsonl`. |
| `scripts/health-check.sh` | Check process liveness, last-run freshness, disk space, and required env vars. Outputs JSON `{"status":"ok|degraded|critical","checks":{...}}`. Always exits 0. |

## Usage

1. Copy this directory into your new project root as `scripts/` and copy `CLAUDE.md.tmpl` to `CLAUDE.md`.
2. Replace all `{{VARIABLE}}` placeholders in `CLAUDE.md`.
3. Edit the placeholder sections in each script to match your project's actual commands.
4. Configure `health-check.sh` via env vars (`HEALTH_PROCESS_NAME`, `HEALTH_PID_FILE`, `HEALTH_MAX_INTERVAL`, `HEALTH_MIN_DISK_MB`, `HEALTH_REQUIRED_VARS`).
5. Add `scripts/health-check.sh` to your uptime monitor or CI health job.
