#!/usr/bin/env bash
# merge-settings.sh — Merge base settings.json with project-type extension
#
# Usage: bash scripts/merge-settings.sh <project-type> [base-path] [output-path]
#
# Arguments:
#   project-type  One of: web-app, cron-bot, trading, payment
#   base-path     Path to base settings.json (default: templates/settings.json)
#   output-path   Where to write merged result (default: stdout)
#
# The script reads the base settings.json deny list and appends
# type-specific deny entries from templates/settings-extensions/<type>.json.
# All other settings (permissions.defaultMode, hooks) are preserved as-is.
#
# Exit codes:
#   0 — success
#   1 — invalid arguments or missing files

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_TYPE="${1:-}"
BASE_PATH="${2:-$SCRIPT_DIR/templates/settings.json}"
OUTPUT_PATH="${3:-}"

# ── Validate ─────────────────────────────────────────────────────
if [ -z "$PROJECT_TYPE" ]; then
  echo "Usage: merge-settings.sh <project-type> [base-path] [output-path]" >&2
  echo "Types: web-app, cron-bot, trading, payment" >&2
  exit 1
fi

EXTENSION_FILE="$SCRIPT_DIR/templates/settings-extensions/${PROJECT_TYPE}.json"

if [ ! -f "$BASE_PATH" ]; then
  echo "Error: base settings not found: $BASE_PATH" >&2
  exit 1
fi

if [ ! -f "$EXTENSION_FILE" ]; then
  echo "Error: no extension for type '$PROJECT_TYPE' at $EXTENSION_FILE" >&2
  echo "Available types:" >&2
  ls "$SCRIPT_DIR/templates/settings-extensions/"*.json 2>/dev/null \
    | xargs -I{} basename {} .json >&2
  exit 1
fi

# ── Merge ────────────────────────────────────────────────────────
# Uses python3 (available on macOS + most Linux) for reliable JSON handling.
MERGED=$(python3 -c "
import json, sys

base_path = sys.argv[1]
ext_path = sys.argv[2]

with open(base_path) as f:
    base = json.load(f)

with open(ext_path) as f:
    ext = json.load(f)

# Append extension deny entries to base deny list
base_deny = base.get('permissions', {}).get('deny', [])
ext_deny = ext.get('deny', [])

# Deduplicate while preserving order
seen = set(base_deny)
for entry in ext_deny:
    if entry not in seen:
        base_deny.append(entry)
        seen.add(entry)

base['permissions']['deny'] = base_deny

print(json.dumps(base, indent=2, ensure_ascii=False))
" "$BASE_PATH" "$EXTENSION_FILE" 2>&1)

if [ $? -ne 0 ]; then
  echo "Error: merge failed: $MERGED" >&2
  exit 1
fi

# ── Output ───────────────────────────────────────────────────────
if [ -n "$OUTPUT_PATH" ]; then
  printf '%s\n' "$MERGED" > "$OUTPUT_PATH"
else
  printf '%s\n' "$MERGED"
fi
