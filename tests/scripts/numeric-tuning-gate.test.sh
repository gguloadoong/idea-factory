#!/usr/bin/env bash
# tests/scripts/numeric-tuning-gate.test.sh — tests for numeric-tuning gate preset
#
# Verifies that templates/gate-presets/numeric-tuning.yml works correctly
# with scripts/run-gate.sh.
#
# Run: bash tests/scripts/numeric-tuning-gate.test.sh
# Or via: bash tests/run-all.sh

set +e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/scripts/run-gate.sh"
PRESET="$ROOT/templates/gate-presets/numeric-tuning.yml"

PASS=0
FAIL=0

# --- Helpers ---

assert_exit() {
  local label="$1"
  local expected="$2"
  local actual="$3"
  if [ "$actual" -eq "$expected" ]; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label (expected exit $expected, got $actual)"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local label="$1"
  local pattern="$2"
  local output="$3"
  if echo "$output" | grep -qE "$pattern"; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label (pattern '$pattern' not found)"
    echo "    output: $(echo "$output" | head -8)"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local label="$1"
  local pattern="$2"
  local output="$3"
  if ! echo "$output" | grep -qE "$pattern"; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label (pattern '$pattern' unexpectedly found)"
    echo "    output: $(echo "$output" | head -8)"
    FAIL=$((FAIL + 1))
  fi
}

echo "numeric-tuning gate preset tests"
echo "================================="

# -----------------------------------------------------------------------
# T1: preset file exists and is loadable
# -----------------------------------------------------------------------
echo ""
echo "T1: preset file exists"
if [ -f "$PRESET" ]; then
  echo "  PASS: T1 preset file exists at $PRESET"
  PASS=$((PASS + 1))
else
  echo "  FAIL: T1 preset file not found at $PRESET"
  FAIL=$((FAIL + 1))
fi

# -----------------------------------------------------------------------
# T2: params.json → architect only (not code-reviewer)
# -----------------------------------------------------------------------
echo ""
echo "T2: params.json → architect only"
output=$(GATE_FILES="config/model.params.json" GATE_RULES="$PRESET" bash "$GATE" 2>&1)
rc=$?
assert_exit "T2 exit code" 0 "$rc"
assert_contains "T2 has architect" "architect" "$output"
assert_not_contains "T2 no code-reviewer" "code-reviewer" "$output"

# -----------------------------------------------------------------------
# T3: constants.js → architect only
# -----------------------------------------------------------------------
echo ""
echo "T3: constants.js → architect only"
output=$(GATE_FILES="src/constants.js" GATE_RULES="$PRESET" bash "$GATE" 2>&1)
rc=$?
assert_exit "T3 exit code" 0 "$rc"
assert_contains "T3 has architect" "architect" "$output"
assert_not_contains "T3 no code-reviewer" "code-reviewer" "$output"

# -----------------------------------------------------------------------
# T4: decisions.md → no reviewers
# -----------------------------------------------------------------------
echo ""
echo "T4: decisions.md → no reviewers"
output=$(GATE_FILES="docs/decisions.md" GATE_RULES="$PRESET" bash "$GATE" 2>&1)
rc=$?
assert_exit "T4 exit code" 0 "$rc"
assert_contains "T4 no reviewers message" "none|no reviewer" "$output"
assert_not_contains "T4 no architect" "selected reviewers:.*architect" "$output"

# -----------------------------------------------------------------------
# T5: general .ts file → default (architect + code-reviewer)
# -----------------------------------------------------------------------
echo ""
echo "T5: general .ts file → default (architect + code-reviewer)"
output=$(GATE_FILES="src/engine/trader.ts" GATE_RULES="$PRESET" bash "$GATE" 2>&1)
rc=$?
assert_exit "T5 exit code" 0 "$rc"
assert_contains "T5 has architect" "architect" "$output"
assert_contains "T5 has code-reviewer" "code-reviewer" "$output"

# -----------------------------------------------------------------------
# T6: threshold file → architect only
# -----------------------------------------------------------------------
echo ""
echo "T6: threshold file → architect only"
output=$(GATE_FILES="config/rsi_threshold.json" GATE_RULES="$PRESET" bash "$GATE" 2>&1)
rc=$?
assert_exit "T6 exit code" 0 "$rc"
assert_contains "T6 has architect" "architect" "$output"
assert_not_contains "T6 no code-reviewer" "code-reviewer" "$output"

# -----------------------------------------------------------------------
# T7: weight file → architect only
# -----------------------------------------------------------------------
echo ""
echo "T7: weight file → architect only"
output=$(GATE_FILES="models/signal_weight.json" GATE_RULES="$PRESET" bash "$GATE" 2>&1)
rc=$?
assert_exit "T7 exit code" 0 "$rc"
assert_contains "T7 has architect" "architect" "$output"
assert_not_contains "T7 no code-reviewer" "code-reviewer" "$output"

# -----------------------------------------------------------------------
# T8: constants.ts → architect only
# -----------------------------------------------------------------------
echo ""
echo "T8: constants.ts → architect only"
output=$(GATE_FILES="src/signals/constants.ts" GATE_RULES="$PRESET" bash "$GATE" 2>&1)
rc=$?
assert_exit "T8 exit code" 0 "$rc"
assert_contains "T8 has architect" "architect" "$output"
assert_not_contains "T8 no code-reviewer" "code-reviewer" "$output"

# -----------------------------------------------------------------------
# T9: exit 0 guaranteed — param file change
# -----------------------------------------------------------------------
echo ""
echo "T9: exit 0 guaranteed for param file change"
output=$(GATE_FILES="strategy.config.json" GATE_RULES="$PRESET" bash "$GATE" 2>&1)
rc=$?
assert_exit "T9 exit code always 0" 0 "$rc"

# -----------------------------------------------------------------------
# T10: exit 0 guaranteed — empty file list
# -----------------------------------------------------------------------
echo ""
echo "T10: exit 0 guaranteed — empty file list"
output=$(GATE_FILES="" GATE_RULES="$PRESET" bash "$GATE" 2>&1)
rc=$?
assert_exit "T10 exit code always 0" 0 "$rc"

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
echo ""
echo "================================="
echo "Results: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

exit 0
