#!/usr/bin/env bash
# backtest.sh — Run a backtest over a date range using a config file.
# Usage: backtest.sh <FROM_DATE> <TO_DATE> <CONFIG_FILE>
# Exit codes: 0 success, 1 invalid args, 2 backtest failure

set -euo pipefail

FROM="${1:-}"
TO="${2:-}"
CONFIG="${3:-}"

# --- Input validation ---
if [[ -z "$FROM" || -z "$TO" || -z "$CONFIG" ]]; then
  echo "Usage: $0 <FROM_DATE> <TO_DATE> <CONFIG_FILE>" >&2
  echo "  FROM_DATE   Start date in YYYY-MM-DD format" >&2
  echo "  TO_DATE     End date in YYYY-MM-DD format" >&2
  echo "  CONFIG_FILE Path to strategy/config JSON file" >&2
  exit 1
fi

if [[ ! -f "$CONFIG" ]]; then
  echo "Error: config file not found: $CONFIG" >&2
  exit 1
fi

# Basic date format check (YYYY-MM-DD)
date_re='^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
if [[ ! "$FROM" =~ $date_re || ! "$TO" =~ $date_re ]]; then
  echo "Error: dates must be in YYYY-MM-DD format (got: '$FROM', '$TO')" >&2
  exit 1
fi

if [[ "$FROM" > "$TO" ]]; then
  echo "Error: FROM_DATE ($FROM) must be <= TO_DATE ($TO)" >&2
  exit 1
fi

# --- Prepare output directory ---
RESULTS_DIR=".omc/experiments"
mkdir -p "$RESULTS_DIR"
RESULT_FILE="$RESULTS_DIR/$(date +%Y-%m-%d)-backtest.json"

echo "Running backtest: $FROM -> $TO using $CONFIG"
echo "Results will be saved to: $RESULT_FILE"

# --- Run backtest ---
# Replace the line below with the actual backtest command for this project.
if ! node src/backtest.js --from "$FROM" --to "$TO" --config "$CONFIG" --output "$RESULT_FILE"; then
  echo "Error: backtest failed (exit code $?)" >&2
  # Write a minimal failure record so CI can inspect it
  printf '{"status":"failed","from":"%s","to":"%s","config":"%s","ts":"%s"}\n' \
    "$FROM" "$TO" "$CONFIG" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$RESULT_FILE"
  exit 2
fi

echo "Backtest complete. Results: $RESULT_FILE"
exit 0
