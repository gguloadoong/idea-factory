#!/usr/bin/env bash
# tests/scripts/run-gate.test.sh — unit tests for scripts/run-gate.sh
#
# Each test verifies a specific behavior. The test suite itself exits 0
# only if all assertions pass. run-gate.sh always exits 0 (advisory only).
#
# Run: bash tests/scripts/run-gate.test.sh
# Or via: bash tests/run-all.sh

set +e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/scripts/run-gate.sh"
RULES="$ROOT/templates/gate-rules.yml"

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

echo "run-gate.sh tests"
echo "================="

# -----------------------------------------------------------------------
# T1: exit 0 always — md-only change
# -----------------------------------------------------------------------
echo ""
echo "T1: exit 0 always — .md only change"
output=$(GATE_FILES="README.md" GATE_RULES="$RULES" bash "$GATE" 2>&1)
rc=$?
assert_exit "T1 exit code" 0 "$rc"

# -----------------------------------------------------------------------
# T2: .md only → no reviewers
# -----------------------------------------------------------------------
echo ""
echo "T2: .md only → no reviewers selected"
output=$(GATE_FILES="README.md" GATE_RULES="$RULES" bash "$GATE" 2>&1)
assert_contains "T2 no reviewers message" "none|no reviewer" "$output"
assert_not_contains "T2 reviewer name absent" "architect" "$output"

# -----------------------------------------------------------------------
# T3: auth file → 4 reviewers (architect, critic, code-reviewer, security-reviewer)
# -----------------------------------------------------------------------
echo ""
echo "T3: src/auth/ file → 4 reviewers"
output=$(GATE_FILES="src/auth/login.ts" GATE_RULES="$RULES" bash "$GATE" 2>&1)
rc=$?
assert_exit "T3 exit code" 0 "$rc"
assert_contains "T3 has architect"         "architect"        "$output"
assert_contains "T3 has critic"            "critic"           "$output"
assert_contains "T3 has code-reviewer"     "code-reviewer"    "$output"
assert_contains "T3 has security-reviewer" "security-reviewer" "$output"

# -----------------------------------------------------------------------
# T4: mixed change (md + auth) → union = 4 reviewers (md contributes none)
# -----------------------------------------------------------------------
echo ""
echo "T4: mixed .md + auth → union of reviewers"
output=$(GATE_FILES="$(printf 'README.md\nsrc/auth/session.ts')" GATE_RULES="$RULES" bash "$GATE" 2>&1)
rc=$?
assert_exit "T4 exit code" 0 "$rc"
assert_contains "T4 has security-reviewer" "security-reviewer" "$output"

# -----------------------------------------------------------------------
# T5: gate-rules.yml absent → default fallback (architect + code-reviewer)
# -----------------------------------------------------------------------
echo ""
echo "T5: missing gate-rules.yml → default fallback"
output=$(GATE_FILES="src/main.ts" GATE_RULES="/nonexistent/gate-rules.yml" bash "$GATE" 2>&1)
rc=$?
assert_exit "T5 exit code" 0 "$rc"
assert_contains "T5 fallback architect"     "architect"     "$output"
assert_contains "T5 fallback code-reviewer" "code-reviewer" "$output"

# -----------------------------------------------------------------------
# T6: --dry-run output shows simulation header
# -----------------------------------------------------------------------
echo ""
echo "T6: --dry-run shows simulation output"
output=$(GATE_FILES="src/app/Button.tsx" GATE_RULES="$RULES" bash "$GATE" --dry-run 2>&1)
rc=$?
assert_exit "T6 exit code" 0 "$rc"
assert_contains "T6 dry-run indicator" "dry.run" "$output"

# -----------------------------------------------------------------------
# T7: empty GATE_FILES → graceful "no changed files" message
# -----------------------------------------------------------------------
echo ""
echo "T7: empty file list → graceful no-op"
output=$(GATE_FILES="" GATE_RULES="$RULES" bash "$GATE" 2>&1)
rc=$?
assert_exit "T7 exit code" 0 "$rc"
assert_contains "T7 no changed files" "no changed files" "$output"

# -----------------------------------------------------------------------
# T8: engine file → architect + code-reviewer (not qa-tester)
# -----------------------------------------------------------------------
echo ""
echo "T8: engine file → architect + code-reviewer (core engine rule)"
output=$(GATE_FILES="src/trade/tradeEngine.ts" GATE_RULES="$RULES" bash "$GATE" 2>&1)
rc=$?
assert_exit "T8 exit code" 0 "$rc"
assert_contains "T8 has architect"     "architect"     "$output"
assert_contains "T8 has code-reviewer" "code-reviewer" "$output"
assert_not_contains "T8 no security"  "security-reviewer" "$output"

# -----------------------------------------------------------------------
# T9: tsx component → architect + code-reviewer + qa-tester
# -----------------------------------------------------------------------
echo ""
echo "T9: .tsx component → architect + code-reviewer + qa-tester"
output=$(GATE_FILES="src/components/Modal.tsx" GATE_RULES="$RULES" bash "$GATE" 2>&1)
rc=$?
assert_exit "T9 exit code" 0 "$rc"
assert_contains "T9 has architect"     "architect"     "$output"
assert_contains "T9 has code-reviewer" "code-reviewer" "$output"
assert_contains "T9 has qa-tester"     "qa-tester"     "$output"

# -----------------------------------------------------------------------
# T10: test file (*.test.ts) → only code-reviewer
# -----------------------------------------------------------------------
echo ""
echo "T10: test file → only code-reviewer"
output=$(GATE_FILES="src/utils/parser.test.ts" GATE_RULES="$RULES" bash "$GATE" 2>&1)
rc=$?
assert_exit "T10 exit code" 0 "$rc"
assert_contains "T10 has code-reviewer" "code-reviewer" "$output"
assert_not_contains "T10 no qa-tester" "qa-tester" "$output"

# -----------------------------------------------------------------------
# T11: config file (*.config.js) → only architect
# -----------------------------------------------------------------------
echo ""
echo "T11: config file → only architect"
output=$(GATE_FILES="jest.config.js" GATE_RULES="$RULES" bash "$GATE" 2>&1)
rc=$?
assert_exit "T11 exit code" 0 "$rc"
assert_contains "T11 has architect" "architect" "$output"
assert_not_contains "T11 no code-reviewer alone" "code-reviewer" "$output"

# -----------------------------------------------------------------------
# T12: unknown file → default reviewers (architect + code-reviewer)
# -----------------------------------------------------------------------
echo ""
echo "T12: unknown file type → default reviewers"
output=$(GATE_FILES="some/random/file.xyz" GATE_RULES="$RULES" bash "$GATE" 2>&1)
rc=$?
assert_exit "T12 exit code" 0 "$rc"
assert_contains "T12 default architect"     "architect"     "$output"
assert_contains "T12 default code-reviewer" "code-reviewer" "$output"

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
echo ""
echo "================="
echo "Results: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

exit 0
