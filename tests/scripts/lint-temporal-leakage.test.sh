#!/usr/bin/env bash
# tests/scripts/lint-temporal-leakage.test.sh — unit tests for scripts/lint-temporal-leakage.sh
#
# Run: bash tests/scripts/lint-temporal-leakage.test.sh
# Or via: bash tests/run-all.sh

set +e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LINT="$ROOT/scripts/lint-temporal-leakage.sh"
PATTERNS="$ROOT/templates/lints/temporal-leakage/patterns.json"

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

# --- Temp dir setup ---
TMPDIR_BASE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

echo "lint-temporal-leakage.sh tests"
echo "==============================="

# -----------------------------------------------------------------------
# T1: patterns.json parses successfully (python3 can load it)
# -----------------------------------------------------------------------
echo ""
echo "T1: patterns.json is valid JSON and parseable"
python3 -c "import json; data=json.load(open('$PATTERNS')); assert len(data['patterns']) >= 6" 2>&1
rc=$?
assert_exit "T1 patterns.json valid JSON with >=6 patterns" 0 "$rc"

# -----------------------------------------------------------------------
# T2: df.shift(-1) detected in Python file (HIGH)
# -----------------------------------------------------------------------
echo ""
echo "T2: df.shift(-1) detected as HIGH"
PY_DIR="$TMPDIR_BASE/t2"
mkdir -p "$PY_DIR"
cat > "$PY_DIR/strategy.py" <<'EOF'
import pandas as pd
df = pd.read_csv("prices.csv")
df["future_ret"] = df["close"].shift(-1) / df["close"] - 1
EOF
output=$(bash "$LINT" --path "$PY_DIR" --lang python 2>&1)
rc=$?
assert_exit "T2 exit 0" 0 "$rc"
assert_contains "T2 shift_negative HIGH detected" "HIGH.*shift_negative|shift_negative.*HIGH" "$output"

# -----------------------------------------------------------------------
# T3: Math.random() detected in JS file (WARN)
# -----------------------------------------------------------------------
echo ""
echo "T3: Math.random() detected in JS file"
JS_DIR="$TMPDIR_BASE/t3"
mkdir -p "$JS_DIR"
cat > "$JS_DIR/backtest.js" <<'EOF'
function getRandomReturn() {
  return Math.random() * 0.02 - 0.01;
}
EOF
output=$(bash "$LINT" --path "$JS_DIR" --lang javascript 2>&1)
rc=$?
assert_exit "T3 exit 0" 0 "$rc"
assert_contains "T3 math_random_unseeded detected" "math_random_unseeded" "$output"

# -----------------------------------------------------------------------
# T4: df.shift(1) — positive shift — no false positive
# -----------------------------------------------------------------------
echo ""
echo "T4: df.shift(1) should NOT trigger shift_negative"
PY_DIR4="$TMPDIR_BASE/t4"
mkdir -p "$PY_DIR4"
cat > "$PY_DIR4/ok_strategy.py" <<'EOF'
import pandas as pd
df = pd.read_csv("prices.csv")
df["prev_close"] = df["close"].shift(1)
EOF
output=$(bash "$LINT" --path "$PY_DIR4" --lang python 2>&1)
rc=$?
assert_exit "T4 exit 0" 0 "$rc"
assert_not_contains "T4 no shift_negative false positive" "shift_negative" "$output"

# -----------------------------------------------------------------------
# T5: empty directory — graceful handling
# -----------------------------------------------------------------------
echo ""
echo "T5: empty directory handled gracefully"
EMPTY_DIR="$TMPDIR_BASE/t5_empty"
mkdir -p "$EMPTY_DIR"
output=$(bash "$LINT" --path "$EMPTY_DIR" 2>&1)
rc=$?
assert_exit "T5 exit 0 on empty dir" 0 "$rc"
assert_contains "T5 graceful no-files message" "no target files" "$output"

# -----------------------------------------------------------------------
# T6: --lang filter — python pattern not fired on JS file
# -----------------------------------------------------------------------
echo ""
echo "T6: --lang javascript skips Python-only patterns"
JS_DIR6="$TMPDIR_BASE/t6"
mkdir -p "$JS_DIR6"
cat > "$JS_DIR6/algo.js" <<'EOF'
// This is JS only
const arr = [1,2,3];
const last = arr.slice(-1);
EOF
output=$(bash "$LINT" --path "$JS_DIR6" --lang javascript 2>&1)
rc=$?
assert_exit "T6 exit 0" 0 "$rc"
# shift_negative is python-only — should NOT appear
assert_not_contains "T6 python-only pattern absent for JS" "shift_negative" "$output"
# js_negative_shift should fire
assert_contains "T6 js_negative_shift detected" "js_negative_shift" "$output"

# -----------------------------------------------------------------------
# T7: iloc[-1] detected in Python file (WARN)
# -----------------------------------------------------------------------
echo ""
echo "T7: iloc[-1] detected in Python file"
PY_DIR7="$TMPDIR_BASE/t7"
mkdir -p "$PY_DIR7"
cat > "$PY_DIR7/signals.py" <<'EOF'
for i in range(len(df)):
    last_price = df.iloc[-1]["close"]
    signal = last_price * 1.01
EOF
output=$(bash "$LINT" --path "$PY_DIR7" --lang python 2>&1)
rc=$?
assert_exit "T7 exit 0" 0 "$rc"
assert_contains "T7 iloc_negative_in_loop detected" "iloc_negative_in_loop" "$output"

# -----------------------------------------------------------------------
# T8: exit 0 guaranteed even with multiple matches
# -----------------------------------------------------------------------
echo ""
echo "T8: exit 0 guaranteed with multiple leakage patterns"
PY_DIR8="$TMPDIR_BASE/t8"
mkdir -p "$PY_DIR8"
cat > "$PY_DIR8/leaky.py" <<'EOF'
import random
import numpy as np
df["future"] = df["close"].shift(-3)
last = df.iloc[-1]["price"]
r = random.random()
n = np.random.rand(10)
EOF
output=$(bash "$LINT" --path "$PY_DIR8" --lang python 2>&1)
rc=$?
assert_exit "T8 exit 0 with multiple matches" 0 "$rc"
assert_contains "T8 summary line present" "temporal-leakage-lint summary" "$output"

# -----------------------------------------------------------------------
# Final summary
# -----------------------------------------------------------------------
echo ""
echo "==============================="
echo "Results: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
