#!/usr/bin/env bash
# check-failed-attempts.sh — SessionStart 훅: 이전 실패 시도 경고
#
# idea-factory v8 item 4.3 (docs/plans/v8-backlog.md Theme 4)
#
# ─────────────────────────────────────────────────────────────────────
# PURPOSE
# ─────────────────────────────────────────────────────────────────────
# At SessionStart time, check .omc/experiments/failed-attempts.jsonl.
# If entries exist (non-comment lines), emit the most recent 10 entries
# as a system-reminder so Claude avoids repeating the same mistakes.
#
# Output (stdout): system-reminder lines if entries found, else silent.
# The Claude Code runtime injects stdout of SessionStart hooks as
# <system-reminder> content into the first turn.
#
# ─────────────────────────────────────────────────────────────────────
# CRITICAL INVARIANT: THIS SCRIPT MUST ALWAYS EXIT 0
# ─────────────────────────────────────────────────────────────────────
# SessionStart hooks must never prevent a session from starting.

trap 'exit 0' ERR EXIT

{
  LEDGER="${FAILED_ATTEMPTS_FILE:-.omc/experiments/failed-attempts.jsonl}"

  # File must exist and be a regular file
  [ -f "$LEDGER" ] 2>/dev/null || exit 0

  # Extract non-comment, non-empty lines via python3 (cross-platform)
  python3 -c '
import sys, json

ledger = sys.argv[1]
entries = []

try:
    with open(ledger, "r") as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            try:
                obj = json.loads(line)
                entries.append(obj)
            except Exception:
                # malformed line — skip silently
                continue
except Exception:
    sys.exit(0)

if not entries:
    sys.exit(0)

# Show only the most recent 10
recent = entries[-10:]

print("이전 세션에서 실패한 시도가 기록되어 있습니다. 같은 접근을 반복하지 마세요:")
for e in recent:
    what = e.get("what", "")
    reason = e.get("reason", "")
    ts = e.get("ts", "")
    prefix = f"[{ts}] " if ts else ""
    print(f"  - {prefix}{what} → {reason}")
' "$LEDGER" 2>/dev/null || true

} 2>/dev/null

# Explicit exit 0 — the most important line in this script.
exit 0
