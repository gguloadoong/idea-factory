#!/usr/bin/env bash
# Tests for templates/hooks/check-decay-counter.sh (v8 item 4.1)
#
# Verifies:
#   1. Exits 0 on every input variant (exit-0 guarantee)
#   2. No output before reaching threshold (silent counting)
#   3. Reinjection message emitted at threshold
#   4. Anti-quit text present in reinjection
#   5. Circuit breaker text present in reinjection
#   6. Counter resets properly per session
#   7. Handles empty/malformed input gracefully

set +e

HOOK="$(cd "$(dirname "$0")/../.." && pwd)/templates/hooks/check-decay-counter.sh"
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

# ── Test 1: exit 0 on empty stdin ────────────────────────────────
echo '' | bash "$HOOK"
RC=$?
assert_eq "$RC" "0" "T1: exit 0 for empty stdin"

# ── Test 2: exit 0 on malformed input ────────────────────────────
echo 'not json' | bash "$HOOK"
RC=$?
assert_eq "$RC" "0" "T2: exit 0 for malformed input"

# ── Test 3: silent before threshold (use small interval=5) ───────
rm -rf .claude 2>/dev/null
export DECAY_REINJECT_INTERVAL=5
export CLAUDE_SESSION_ID="test-silent"
export CLAUDE_AUDIT_DIR=".claude/audit"

OUTPUT=""
for i in 1 2 3 4; do
  STEP_OUT=$(echo '{}' | bash "$HOOK" 2>/dev/null)
  if [ -n "$STEP_OUT" ]; then
    OUTPUT="$STEP_OUT"
  fi
done

if [ -n "$OUTPUT" ]; then
  fail "T3: output emitted before threshold (invocation <5)"
fi

# ── Test 4: reinjection at threshold ─────────────────────────────
# 5th invocation should trigger
REINJECT_OUT=$(echo '{}' | bash "$HOOK" 2>/dev/null)
RC=$?
assert_eq "$RC" "0" "T4: exit 0 at threshold"

if [ -z "$REINJECT_OUT" ]; then
  fail "T4: no reinjection output at threshold (invocation 5)"
fi

# ── Test 5: anti-quit text present ───────────────────────────────
if ! printf '%s' "$REINJECT_OUT" | grep -q "ANTI-QUIT" 2>/dev/null; then
  fail "T5: ANTI-QUIT keyword missing from reinjection"
fi

# ── Test 6: circuit breaker text present ─────────────────────────
if ! printf '%s' "$REINJECT_OUT" | grep -q "CIRCUIT BREAKER" 2>/dev/null; then
  fail "T6: CIRCUIT BREAKER keyword missing from reinjection"
fi

# ── Test 7: counter placeholder replaced with actual number ──────
if printf '%s' "$REINJECT_OUT" | grep -q "COUNTER_PLACEHOLDER" 2>/dev/null; then
  fail "T7: COUNTER_PLACEHOLDER not replaced with actual count"
fi
if ! printf '%s' "$REINJECT_OUT" | grep -q "#5" 2>/dev/null; then
  fail "T7: expected '#5' in reinjection output"
fi

# ── Test 8: silent again after threshold until next cycle ────────
BETWEEN_OUT=$(echo '{}' | bash "$HOOK" 2>/dev/null)
if [ -n "$BETWEEN_OUT" ]; then
  fail "T8: output emitted between thresholds (invocation 6)"
fi

# ── Test 9: fires again at 2x threshold ─────────────────────────
for i in 7 8 9; do
  echo '{}' | bash "$HOOK" >/dev/null 2>&1
done
SECOND_REINJECT=$(echo '{}' | bash "$HOOK" 2>/dev/null)
if [ -z "$SECOND_REINJECT" ]; then
  fail "T9: no reinjection at 2x threshold (invocation 10)"
fi

# ── Test 10: different session ID = independent counter ──────────
export CLAUDE_SESSION_ID="test-other-session"
ISOLATED_OUT=$(echo '{}' | bash "$HOOK" 2>/dev/null)
if [ -n "$ISOLATED_OUT" ]; then
  fail "T10: different session should start at count 1, not trigger"
fi

# ── Test 11: .gitignore auto-created ─────────────────────────────
if [ ! -f .claude/audit/.gitignore ]; then
  fail "T11: .gitignore not auto-created"
fi

# ── Test 12: counter file contains valid number ──────────────────
COUNTER_FILE=".claude/audit/.decay-counter-test-silent"
if [ -f "$COUNTER_FILE" ]; then
  VAL=$(cat "$COUNTER_FILE")
  case "$VAL" in
    ''|*[!0-9]*) fail "T12: counter file contains non-numeric: '$VAL'" ;;
    *) ;; # ok
  esac
else
  fail "T12: counter file not created"
fi

# ── Summary ───────────────────────────────────────────────────────
if [ "$FAILED" -gt 0 ]; then
  echo ""
  echo "check-decay-counter: $FAILED assertion(s) failed"
  exit 1
fi

echo "check-decay-counter: 12 assertions passed"
exit 0
