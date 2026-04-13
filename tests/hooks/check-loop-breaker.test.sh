#!/usr/bin/env bash
# Tests for templates/hooks/check-loop-breaker.sh (v8 item 3.1)
#
# Verifies:
#   1. Exits 0 on every input variant (exit-0 guarantee)
#   2. No warning for first/second edit of same file
#   3. Warning emitted at 3rd edit of same file
#   4. Escalation emitted at 5th edit
#   5. Different files don't trigger each other
#   6. Window rolling prevents unbounded ledger growth
#   7. Handles empty/malformed input gracefully

set +e

HOOK="$(cd "$(dirname "$0")/../.." && pwd)/templates/hooks/check-loop-breaker.sh"
if [ ! -x "$HOOK" ]; then
  echo "  FAIL: hook not executable at $HOOK"
  exit 1
fi

TMPDIR=$(mktemp -d 2>/dev/null || mktemp -d -t idea-factory 2>/dev/null)
if [ -z "$TMPDIR" ] || [ ! -d "$TMPDIR" ]; then
  echo "  FAIL: could not create temp directory"
  exit 1
fi
trap 'rm -rf "$TMPDIR"' EXIT
cd "$TMPDIR" || exit 1

FAILED=0

fail() {
  echo "  FAIL: $1"
  FAILED=$((FAILED + 1))
}

assert_eq() {
  [ "$1" = "$2" ] || fail "$3 — expected '$2', got '$1'"
}

# ── Shared config ────────────────────────────────────────────────
export CLAUDE_AUDIT_DIR=".claude/audit"
export CLAUDE_SESSION_ID="test-loop"
export LOOP_WARN_THRESHOLD=3
export LOOP_ESCALATE_THRESHOLD=5
export LOOP_WINDOW_SIZE=15

make_payload() {
  printf '{"tool_input":{"file_path":"%s"}}' "$1"
}

# ── Test 1: exit 0 on empty stdin ────────────────────────────────
echo '' | bash "$HOOK"
RC=$?
assert_eq "$RC" "0" "T1: exit 0 for empty stdin"

# ── Test 2: exit 0 on malformed JSON ────────────────────────────
echo 'not json' | bash "$HOOK"
RC=$?
assert_eq "$RC" "0" "T2: exit 0 for malformed JSON"

# ── Test 3: exit 0 on missing file_path ──────────────────────────
echo '{"tool_input":{}}' | bash "$HOOK"
RC=$?
assert_eq "$RC" "0" "T3: exit 0 for missing file_path"

# ── Test 4: no warning on 1st and 2nd edit ───────────────────────
rm -rf .claude 2>/dev/null
OUT1=$(make_payload "/src/app.ts" | bash "$HOOK" 2>/dev/null)
assert_eq "$?" "0" "T4a: exit 0 on 1st edit"
if [ -n "$OUT1" ]; then
  fail "T4a: output on 1st edit"
fi

OUT2=$(make_payload "/src/app.ts" | bash "$HOOK" 2>/dev/null)
assert_eq "$?" "0" "T4b: exit 0 on 2nd edit"
if [ -n "$OUT2" ]; then
  fail "T4b: output on 2nd edit"
fi

# ── Test 5: warning on 3rd edit ──────────────────────────────────
OUT3=$(make_payload "/src/app.ts" | bash "$HOOK" 2>/dev/null)
assert_eq "$?" "0" "T5: exit 0 on 3rd edit"
if [ -z "$OUT3" ]; then
  fail "T5: no warning on 3rd edit"
fi
if ! printf '%s' "$OUT3" | grep -q "WARNING" 2>/dev/null; then
  fail "T5: WARNING keyword missing"
fi

# ── Test 6: still warning on 4th edit ────────────────────────────
OUT4=$(make_payload "/src/app.ts" | bash "$HOOK" 2>/dev/null)
assert_eq "$?" "0" "T6: exit 0 on 4th edit"
if [ -z "$OUT4" ]; then
  fail "T6: no warning on 4th edit"
fi

# ── Test 7: escalation on 5th edit ───────────────────────────────
OUT5=$(make_payload "/src/app.ts" | bash "$HOOK" 2>/dev/null)
assert_eq "$?" "0" "T7: exit 0 on 5th edit"
if [ -z "$OUT5" ]; then
  fail "T7: no output on 5th edit"
fi
if ! printf '%s' "$OUT5" | grep -q "ESCALATE" 2>/dev/null; then
  fail "T7: ESCALATE keyword missing on 5th edit"
fi

# ── Test 8: different file doesn't trigger ───────────────────────
# Reset session
export CLAUDE_SESSION_ID="test-loop-isolated"
rm -rf .claude 2>/dev/null

make_payload "/src/a.ts" | bash "$HOOK" >/dev/null 2>&1
make_payload "/src/b.ts" | bash "$HOOK" >/dev/null 2>&1
OUT_DIFF=$(make_payload "/src/c.ts" | bash "$HOOK" 2>/dev/null)
assert_eq "$?" "0" "T8: exit 0"
if [ -n "$OUT_DIFF" ]; then
  fail "T8: warning triggered for 3 different files"
fi

# ── Test 9: window rolling prevents unbounded growth ─────────────
export CLAUDE_SESSION_ID="test-loop-window"
export LOOP_WINDOW_SIZE=5
rm -rf .claude 2>/dev/null

# Write 10 entries for different files, then check ledger size
for i in $(seq 1 10); do
  make_payload "/src/file${i}.ts" | bash "$HOOK" >/dev/null 2>&1
done

LEDGER=".claude/audit/.loop-ledger-test-loop-window"
if [ -f "$LEDGER" ]; then
  LINES=$(wc -l < "$LEDGER" | tr -d ' ')
  if [ "$LINES" -gt 5 ]; then
    fail "T9: ledger has $LINES lines, expected <= 5 (window size)"
  fi
else
  fail "T9: ledger file not created"
fi

# ── Test 10: .gitignore auto-created ─────────────────────────────
if [ ! -f .claude/audit/.gitignore ]; then
  fail "T10: .gitignore not auto-created"
fi

# ── Test 11: audit JSONL created on escalation ───────────────────
export CLAUDE_SESSION_ID="test-loop-audit"
rm -rf .claude 2>/dev/null
for i in $(seq 1 5); do
  make_payload "/src/audit-test.ts" | bash "$HOOK" >/dev/null 2>&1
done
TODAY=$(date +%Y-%m-%d)
AUDIT_LOG=".claude/audit/loop-breaker-$TODAY.jsonl"
if [ -f "$AUDIT_LOG" ]; then
  python3 -c "
import json
with open('$AUDIT_LOG') as f:
    for line in f:
        if line.strip():
            d = json.loads(line)
            assert d['level'] == 'escalate', f'expected escalate, got {d[\"level\"]}'
            assert d['hits'] >= 5, f'expected hits>=5, got {d[\"hits\"]}'
  " 2>/dev/null || fail "T11: audit JSONL invalid or wrong content"
else
  fail "T11: audit JSONL not created on escalation"
fi

# ── Summary ───────────────────────────────────────────────────────
if [ "$FAILED" -gt 0 ]; then
  echo ""
  echo "check-loop-breaker: $FAILED assertion(s) failed"
  exit 1
fi

echo "check-loop-breaker: 11 assertions passed"
exit 0
