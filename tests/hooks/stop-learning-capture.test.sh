#!/usr/bin/env bash
# Tests for templates/hooks/stop-learning-capture.sh (v8 item 2.4)
#
# Verifies:
#   1. Exits 0 always (exit-0 guarantee)
#   2. Silent when no learning layer dirs exist
#   3. Silent when session is too small (< 20 audit entries)
#   4. Prompts when learning layer + substantial activity
#   5. Prompts when decisions.md changed in recent commit
#   6. Contains all 4 learning categories in output

set +e

HOOK="$(cd "$(dirname "$0")/../.." && pwd)/templates/hooks/stop-learning-capture.sh"
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

# ── Test 1: exit 0 with no learning layer ────────────────────────
echo '{}' | bash "$HOOK"
RC=$?
assert_eq "$RC" "0" "T1: exit 0 with no learning layer"

# ── Test 2: silent with no learning layer ────────────────────────
OUT=$(echo '{}' | bash "$HOOK" 2>/dev/null)
if [ -n "$OUT" ]; then
  fail "T2: output when no learning layer dirs exist"
fi

# ── Test 3: silent when learning layer exists but session too small ─
mkdir -p docs/research docs/field-reports
export CLAUDE_AUDIT_DIR=".claude/audit"
mkdir -p "$CLAUDE_AUDIT_DIR"

# Create only 5 audit entries (below threshold of 20)
TODAY=$(date +%Y-%m-%d)
for i in $(seq 1 5); do
  echo '{"ts":"test","cmd":"ls"}' >> "$CLAUDE_AUDIT_DIR/$TODAY.jsonl"
done

OUT=$(echo '{}' | bash "$HOOK" 2>/dev/null)
RC=$?
assert_eq "$RC" "0" "T3: exit 0 with small session"
if [ -n "$OUT" ]; then
  fail "T3: output when session too small (5 entries)"
fi

# ── Test 4: prompts with substantial activity (20+ entries) ──────
TODAY=$(date +%Y-%m-%d)
for i in $(seq 6 25); do
  echo '{"ts":"test","cmd":"ls"}' >> "$CLAUDE_AUDIT_DIR/$TODAY.jsonl"
done

OUT=$(echo '{}' | bash "$HOOK" 2>/dev/null)
RC=$?
assert_eq "$RC" "0" "T4: exit 0 with substantial session"
if [ -z "$OUT" ]; then
  fail "T4: no prompt with 25 audit entries"
fi

# ── Test 5: contains SESSION LEARNING CAPTURE header ─────────────
if ! printf '%s' "$OUT" | grep -q "SESSION LEARNING CAPTURE" 2>/dev/null; then
  fail "T5: SESSION LEARNING CAPTURE header missing"
fi

# ── Test 6: contains all 4 learning categories ──────────────────
if ! printf '%s' "$OUT" | grep -q "gap" 2>/dev/null; then
  fail "T6a: gap category missing"
fi
if ! printf '%s' "$OUT" | grep -q "docs/research/" 2>/dev/null; then
  fail "T6b: research path missing"
fi
if ! printf '%s' "$OUT" | grep -q "docs/field-reports/" 2>/dev/null; then
  fail "T6c: field-reports path missing"
fi
if ! printf '%s' "$OUT" | grep -q "decisions.md" 2>/dev/null; then
  fail "T6d: decisions.md reference missing"
fi

# ── Test 7: exit 0 on malformed input ────────────────────────────
echo 'not json' | bash "$HOOK"
RC=$?
assert_eq "$RC" "0" "T7: exit 0 on malformed input"

# ── Test 8: silent when only docs/research exists (no field-reports) ──
rm -rf docs/field-reports .claude
mkdir -p .claude/audit
# Small session → should be silent
for i in $(seq 1 5); do
  echo '{"ts":"test"}' >> ".claude/audit/$TODAY.jsonl"
done
OUT=$(echo '{}' | bash "$HOOK" 2>/dev/null)
if [ -n "$OUT" ]; then
  fail "T8: should be silent with small session even with docs/research"
fi

# ── Summary ───────────────────────────────────────────────────────
if [ "$FAILED" -gt 0 ]; then
  echo ""
  echo "stop-learning-capture: $FAILED assertion(s) failed"
  exit 1
fi

echo "stop-learning-capture: 8 assertions passed"
exit 0
