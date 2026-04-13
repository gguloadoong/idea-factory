#!/usr/bin/env bash
# runtime-ratchet.sh — Runtime Metrics Quality Ratchet
#
# Usage: bash scripts/runtime-ratchet.sh --config .ratchet.yml [--check|--update] [--allow-exec]
#
# Modes:
#   --check   Collect current metrics, compare to baseline, warn on regression
#   --update  Collect current metrics, save as new baseline
#
# Security:
#   --allow-exec  Required to execute 'source' commands from config.
#                 Without this flag, source commands are blocked (dry-run listed only).
#
# Config: .ratchet.yml (YAML, parsed with stdlib awk — no PyYAML required)
# Baseline: .ratchet-baseline.json
#
# Exit: Always 0 (advisory only — never blocks pipeline)

set +e
trap 'exit 0' ERR EXIT

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[ratchet]${NC} $*"; }
ok()    { echo -e "${GREEN}[PASS]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail()  { echo -e "${RED}[FAIL]${NC} $*"; }

# ── Argument parsing ──────────────────────────────────────────────────────────
CONFIG=".ratchet.yml"
MODE=""
ALLOW_EXEC=0

while [ $# -gt 0 ]; do
  case "$1" in
    --config)    CONFIG="$2"; shift 2 ;;
    --check)     MODE="check";  shift ;;
    --update)    MODE="update"; shift ;;
    --allow-exec) ALLOW_EXEC=1; shift ;;
    *) shift ;;
  esac
done

BASELINE="${CONFIG%.yml}-baseline.json"
BASELINE="${BASELINE#.}"       # strip leading dot if config had one
BASELINE=".ratchet-baseline.json"

# ── Guard: config must exist ──────────────────────────────────────────────────
if [ ! -f "$CONFIG" ]; then
  warn "Config file '$CONFIG' not found — skipping ratchet check."
  exit 0
fi

# ── Guard: mode required ──────────────────────────────────────────────────────
if [ -z "$MODE" ]; then
  warn "No mode specified. Use --check or --update."
  exit 0
fi

# ── YAML parser (stdlib awk, no PyYAML) ───────────────────────────────────────
# Parses a simple flat-list YAML structure:
#   metrics:
#     - name: foo
#       source: "cmd"
#       threshold: 0.05
#       direction: lower_is_better
#
# Outputs lines: NAME|SOURCE|THRESHOLD|DIRECTION
parse_metrics() {
  local config_file="$1"
  awk '
    /^[[:space:]]*- name:/ {
      if (name != "") print name "|" source "|" threshold "|" direction
      name = ""; source = ""; threshold = ""; direction = ""
      sub(/.*- name:[[:space:]]*/, ""); name = $0
    }
    /^[[:space:]]+source:/ {
      sub(/.*source:[[:space:]]*/, ""); source = $0
      gsub(/^"|"$/, "", source)
    }
    /^[[:space:]]+threshold:/ {
      sub(/.*threshold:[[:space:]]*/, ""); threshold = $0
    }
    /^[[:space:]]+direction:/ {
      sub(/.*direction:[[:space:]]*/, ""); direction = $0
    }
    END {
      if (name != "") print name "|" source "|" threshold "|" direction
    }
  ' "$config_file"
}

# ── Metric collection ─────────────────────────────────────────────────────────
collect_metric() {
  local source_cmd="$1"
  if [ "$ALLOW_EXEC" -eq 0 ]; then
    warn "source command blocked (--allow-exec not set): $source_cmd"
    echo ""
    return
  fi
  # Execute in a subshell to isolate environment; capture stdout only
  local result
  result=$(eval "$source_cmd" 2>/dev/null) || true
  # Strip whitespace
  echo "$result" | tr -d '[:space:]'
}

# ── Baseline read/write ───────────────────────────────────────────────────────
read_baseline() {
  local name="$1"
  if [ ! -f "$BASELINE" ]; then
    echo ""
    return
  fi
  # Extract value for key using awk — no jq dependency
  awk -v key="\"$name\"" '
    $0 ~ key {
      split($0, a, ":")
      val = a[2]
      gsub(/[[:space:],"}]/, "", val)
      print val
      exit
    }
  ' "$BASELINE"
}

write_baseline() {
  local -a names=("${@}")
  # Build JSON object from parallel arrays METRIC_NAMES / METRIC_VALUES
  local json="{"
  local first=1
  local i
  for i in "${!METRIC_NAMES[@]}"; do
    local n="${METRIC_NAMES[$i]}"
    local v="${METRIC_VALUES[$i]}"
    [ "$first" -eq 1 ] || json="$json,"
    json="$json\"$n\":$v"
    first=0
  done
  json="$json}"
  echo "$json" > "$BASELINE"
}

# ── Comparison logic ──────────────────────────────────────────────────────────
# Returns "PASS", "FAIL", or "SKIP" (when values unavailable)
compare_metric() {
  local name="$1"
  local current="$2"
  local baseline="$3"
  local threshold="$4"
  local direction="$5"

  # If either value is empty, skip
  if [ -z "$current" ] || [ -z "$baseline" ]; then
    echo "SKIP"
    return
  fi

  # Use awk for floating-point arithmetic
  awk -v cur="$current" -v base="$baseline" -v thr="$threshold" -v dir="$direction" '
  BEGIN {
    if (dir == "lower_is_better") {
      # Regression: current significantly worse (higher) than baseline
      # FAIL when: current > baseline * (1 + threshold)
      limit = base * (1 + thr)
      if (cur > limit) { print "FAIL"; exit }
    } else {
      # higher_is_better
      # FAIL when: current < baseline * (1 - threshold)
      limit = base * (1 - thr)
      if (cur < limit) { print "FAIL"; exit }
    }
    print "PASS"
  }'
}

# ── Main ──────────────────────────────────────────────────────────────────────
info "Runtime Metrics Ratchet — mode: $MODE | config: $CONFIG"
echo ""

# Parse metrics from config
METRIC_LINES=()
while IFS= read -r line; do
  [ -n "$line" ] && METRIC_LINES+=("$line")
done < <(parse_metrics "$CONFIG")

if [ "${#METRIC_LINES[@]}" -eq 0 ]; then
  warn "No metrics defined in '$CONFIG' — nothing to do."
  exit 0
fi

# Collect current values
METRIC_NAMES=()
METRIC_VALUES=()
METRIC_THRESHOLDS=()
METRIC_DIRECTIONS=()
METRIC_SOURCES=()

for line in "${METRIC_LINES[@]}"; do
  IFS='|' read -r m_name m_source m_threshold m_direction <<< "$line"
  m_name="${m_name// /}"
  m_threshold="${m_threshold// /}"
  m_direction="${m_direction// /}"

  info "Collecting: $m_name (source: $m_source)"
  m_value=$(collect_metric "$m_source")

  METRIC_NAMES+=("$m_name")
  METRIC_VALUES+=("${m_value:-0}")
  METRIC_THRESHOLDS+=("$m_threshold")
  METRIC_DIRECTIONS+=("$m_direction")
  METRIC_SOURCES+=("$m_source")
done

echo ""

# ── UPDATE mode ───────────────────────────────────────────────────────────────
if [ "$MODE" = "update" ]; then
  write_baseline "${METRIC_NAMES[@]}"
  ok "Baseline updated → $BASELINE"
  for i in "${!METRIC_NAMES[@]}"; do
    info "  ${METRIC_NAMES[$i]} = ${METRIC_VALUES[$i]}"
  done
  exit 0
fi

# ── CHECK mode ────────────────────────────────────────────────────────────────
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

for i in "${!METRIC_NAMES[@]}"; do
  n="${METRIC_NAMES[$i]}"
  v="${METRIC_VALUES[$i]}"
  thr="${METRIC_THRESHOLDS[$i]}"
  dir="${METRIC_DIRECTIONS[$i]}"

  baseline_val=$(read_baseline "$n")

  if [ -z "$baseline_val" ]; then
    warn "$n — no baseline found (run --update first)"
    SKIP_COUNT=$((SKIP_COUNT + 1))
    continue
  fi

  result=$(compare_metric "$n" "$v" "$baseline_val" "$thr" "$dir")

  case "$result" in
    PASS)
      ok "$n — current=$v baseline=$baseline_val threshold=$thr direction=$dir"
      PASS_COUNT=$((PASS_COUNT + 1))
      ;;
    FAIL)
      fail "$n — REGRESSION: current=$v baseline=$baseline_val threshold=$thr direction=$dir"
      FAIL_COUNT=$((FAIL_COUNT + 1))
      ;;
    SKIP)
      warn "$n — skipped (value unavailable)"
      SKIP_COUNT=$((SKIP_COUNT + 1))
      ;;
  esac
done

echo ""
info "Results: ${PASS_COUNT} passed, ${FAIL_COUNT} regression(s), ${SKIP_COUNT} skipped"

if [ "$FAIL_COUNT" -gt 0 ]; then
  warn "Runtime metric regression(s) detected — advisory only, pipeline not blocked."
fi

exit 0
