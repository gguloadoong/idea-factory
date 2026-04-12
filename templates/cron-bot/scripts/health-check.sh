#!/usr/bin/env bash
# health-check.sh — Report bot health as JSON. Always exits 0.
# Usage: health-check.sh
# Output: {"status":"ok|degraded|critical","checks":{...}}

# --- Configuration (edit these for your project) ---
PROCESS_NAME="${HEALTH_PROCESS_NAME:-node}"       # process name to check with pgrep
PID_FILE="${HEALTH_PID_FILE:-.bot.pid}"           # optional PID file path
MAX_INTERVAL_SECONDS="${HEALTH_MAX_INTERVAL:-3600}" # max seconds since last successful run
MIN_DISK_MB="${HEALTH_MIN_DISK_MB:-500}"          # minimum free disk space in MB
LAST_SUCCESS_FILE="${HEALTH_LAST_SUCCESS_FILE:-.last_success}"
REQUIRED_ENV_VARS="${HEALTH_REQUIRED_VARS:-}"     # space-separated list of required env var names

# --- Helper: emit final JSON and exit 0 ---
finish() {
  local status="$1"
  local checks_json="$2"
  printf '{"status":"%s","checks":%s}\n' "$status" "$checks_json"
  exit 0
}

checks="{}"
overall="ok"

# --- 1. Process running check ---
process_ok=false
process_detail="not running"

if [[ -n "$PID_FILE" && -f "$PID_FILE" ]]; then
  pid=$(cat "$PID_FILE" 2>/dev/null || true)
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    process_ok=true
    process_detail="running (pid $pid)"
  else
    process_detail="pid file exists but process $pid is dead"
  fi
elif pgrep -x "$PROCESS_NAME" >/dev/null 2>&1; then
  process_ok=true
  process_detail="running (pgrep match)"
fi

if $process_ok; then
  checks=$(printf '%s' "$checks" | sed 's/}$/,"process":{"ok":true,"detail":"'"$process_detail"'"}}/')
else
  checks=$(printf '%s' "$checks" | sed 's/}$/,"process":{"ok":false,"detail":"'"$process_detail"'"}}/')
  overall="critical"
fi

# --- 2. Last successful run within expected interval ---
interval_ok=false
interval_detail="no last_success file found"

if [[ -f "$LAST_SUCCESS_FILE" ]]; then
  last_ts=$(cat "$LAST_SUCCESS_FILE" 2>/dev/null | tr -d '[:space:]')
  now_epoch=$(date +%s)
  # Try to parse as epoch directly, else use date -d (GNU) or date -j (BSD)
  if [[ "$last_ts" =~ ^[0-9]+$ ]]; then
    last_epoch="$last_ts"
  else
    last_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$last_ts" +%s 2>/dev/null \
      || date -d "$last_ts" +%s 2>/dev/null \
      || echo 0)
  fi
  elapsed=$(( now_epoch - last_epoch ))
  if (( elapsed <= MAX_INTERVAL_SECONDS )); then
    interval_ok=true
    interval_detail="last run ${elapsed}s ago (max ${MAX_INTERVAL_SECONDS}s)"
  else
    interval_detail="last run ${elapsed}s ago — exceeds max ${MAX_INTERVAL_SECONDS}s"
  fi
fi

if $interval_ok; then
  checks=$(printf '%s' "$checks" | sed 's/}$/,"last_run":{"ok":true,"detail":"'"$interval_detail"'"}}/')
else
  checks=$(printf '%s' "$checks" | sed 's/}$/,"last_run":{"ok":false,"detail":"'"$interval_detail"'"}}/')
  [[ "$overall" == "ok" ]] && overall="degraded"
fi

# --- 3. Disk space check ---
disk_ok=false
disk_detail="unable to determine"

free_mb=$(df -m . 2>/dev/null | awk 'NR==2{print $4}' || echo 0)
if (( free_mb >= MIN_DISK_MB )); then
  disk_ok=true
  disk_detail="${free_mb}MB free (min ${MIN_DISK_MB}MB)"
else
  disk_detail="${free_mb}MB free — below min ${MIN_DISK_MB}MB"
fi

if $disk_ok; then
  checks=$(printf '%s' "$checks" | sed 's/}$/,"disk":{"ok":true,"detail":"'"$disk_detail"'"}}/')
else
  checks=$(printf '%s' "$checks" | sed 's/}$/,"disk":{"ok":false,"detail":"'"$disk_detail"'"}}/')
  [[ "$overall" == "ok" ]] && overall="degraded"
fi

# --- 4. Required env vars check ---
env_ok=true
env_missing=""

if [[ -n "$REQUIRED_ENV_VARS" ]]; then
  for var in $REQUIRED_ENV_VARS; do
    if [[ -z "${!var:-}" ]]; then
      env_ok=false
      env_missing="${env_missing}${var} "
    fi
  done
fi

env_detail="${env_missing:-all present}"
if $env_ok; then
  checks=$(printf '%s' "$checks" | sed 's/}$/,"env_vars":{"ok":true,"detail":"all present"}}/')
else
  checks=$(printf '%s' "$checks" | sed 's/}$/,"env_vars":{"ok":false,"detail":"missing: '"$env_missing"'"}}/')
  overall="critical"
fi

# --- Emit result ---
finish "$overall" "$checks"
