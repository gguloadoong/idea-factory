#!/usr/bin/env bash
# Tests for scripts/merge-settings.sh (v8 item 1.3)
#
# Verifies:
#   1. Exits 1 with no arguments
#   2. Exits 1 with invalid project type
#   3. web-app merges correctly (adds vercel --prod deny)
#   4. trading merges correctly (adds trading-specific denies)
#   5. payment merges correctly (adds stripe/PCI denies)
#   6. cron-bot merges correctly
#   7. No duplicate entries after merge
#   8. Hooks preserved unchanged
#   9. Output to file works
#  10. Base deny entries preserved

set +e

SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/scripts/merge-settings.sh"
if [ ! -f "$SCRIPT" ]; then
  echo "  FAIL: script not found at $SCRIPT"
  exit 1
fi

FAILED=0

fail() {
  echo "  FAIL: $1"
  FAILED=$((FAILED + 1))
}

# ── Test 1: exits 1 with no arguments ───────────────────────────
bash "$SCRIPT" 2>/dev/null
RC=$?
[ "$RC" -eq 1 ] || fail "T1: expected exit 1 with no args, got $RC"

# ── Test 2: exits 1 with invalid project type ───────────────────
bash "$SCRIPT" "nonexistent-type" 2>/dev/null
RC=$?
[ "$RC" -eq 1 ] || fail "T2: expected exit 1 for invalid type, got $RC"

# ── Test 3: web-app merge adds vercel --prod ─────────────────────
OUT=$(bash "$SCRIPT" "web-app" 2>/dev/null)
RC=$?
[ "$RC" -eq 0 ] || fail "T3: web-app merge failed with exit $RC"
if ! printf '%s' "$OUT" | grep -q 'vercel --prod' 2>/dev/null; then
  fail "T3: vercel --prod not in web-app merge output"
fi

# ── Test 4: trading merge has trading-specific entries ───────────
OUT=$(bash "$SCRIPT" "trading" 2>/dev/null)
RC=$?
[ "$RC" -eq 0 ] || fail "T4: trading merge failed with exit $RC"
if ! printf '%s' "$OUT" | grep -q 'REAL_MONEY' 2>/dev/null; then
  fail "T4a: REAL_MONEY deny not in trading merge"
fi
if ! printf '%s' "$OUT" | grep -q 'FLUSHDB' 2>/dev/null; then
  fail "T4b: FLUSHDB deny not in trading merge"
fi
if ! printf '%s' "$OUT" | grep -q 'binance' 2>/dev/null; then
  fail "T4c: binance deny not in trading merge"
fi

# ── Test 5: payment merge has stripe/PCI entries ─────────────────
OUT=$(bash "$SCRIPT" "payment" 2>/dev/null)
RC=$?
[ "$RC" -eq 0 ] || fail "T5: payment merge failed with exit $RC"
if ! printf '%s' "$OUT" | grep -q 'stripe' 2>/dev/null; then
  fail "T5a: stripe deny not in payment merge"
fi
if ! printf '%s' "$OUT" | grep -q 'tosspayments' 2>/dev/null; then
  fail "T5b: tosspayments deny not in payment merge"
fi

# ── Test 6: cron-bot merge works ─────────────────────────────────
OUT=$(bash "$SCRIPT" "cron-bot" 2>/dev/null)
RC=$?
[ "$RC" -eq 0 ] || fail "T6: cron-bot merge failed with exit $RC"
if ! printf '%s' "$OUT" | grep -q 'pm2' 2>/dev/null; then
  fail "T6a: pm2 deny not in cron-bot merge"
fi
if ! printf '%s' "$OUT" | grep -q 'crontab' 2>/dev/null; then
  fail "T6b: crontab deny not in cron-bot merge"
fi

# ── Test 7: no duplicate entries ─────────────────────────────────
OUT=$(bash "$SCRIPT" "web-app" 2>/dev/null)
# Count occurrences of "rm -rf /" — should appear exactly once
COUNT=$(printf '%s' "$OUT" | grep -c 'rm -rf /' 2>/dev/null || echo 0)
[ "$COUNT" -eq 1 ] || fail "T7: duplicate base deny entry (rm -rf / appears $COUNT times)"

# ── Test 8: hooks preserved unchanged ────────────────────────────
OUT=$(bash "$SCRIPT" "trading" 2>/dev/null)
if ! printf '%s' "$OUT" | grep -q 'check-audit.sh' 2>/dev/null; then
  fail "T8a: hooks not preserved (check-audit.sh missing)"
fi
if ! printf '%s' "$OUT" | grep -q 'check-decay-counter.sh' 2>/dev/null; then
  fail "T8b: hooks not preserved (check-decay-counter.sh missing)"
fi
if ! printf '%s' "$OUT" | grep -q 'stop-learning-capture.sh' 2>/dev/null; then
  fail "T8c: hooks not preserved (stop-learning-capture.sh missing)"
fi

# ── Test 9: output to file works ────────────────────────────────
TMPFILE=$(mktemp 2>/dev/null || mktemp -t merge-test 2>/dev/null)
trap 'rm -f "$TMPFILE"' EXIT
bash "$SCRIPT" "web-app" "" "$TMPFILE" 2>/dev/null
RC=$?
[ "$RC" -eq 0 ] || fail "T9: output to file failed with exit $RC"
if [ ! -s "$TMPFILE" ]; then
  fail "T9: output file is empty"
fi
# Verify it's valid JSON
python3 -c "import json; json.load(open('$TMPFILE'))" 2>/dev/null
[ $? -eq 0 ] || fail "T9: output file is not valid JSON"

# ── Test 10: base deny entries preserved ─────────────────────────
OUT=$(bash "$SCRIPT" "trading" 2>/dev/null)
if ! printf '%s' "$OUT" | grep -q 'rm -rf ~' 2>/dev/null; then
  fail "T10a: base deny 'rm -rf ~' missing after merge"
fi
if ! printf '%s' "$OUT" | grep -q 'credentials' 2>/dev/null; then
  fail "T10b: base deny 'credentials' missing after merge"
fi

# ── Summary ──────────────────────────────────────────────────────
if [ "$FAILED" -gt 0 ]; then
  echo ""
  echo "merge-settings: $FAILED assertion(s) failed"
  exit 1
fi

echo "merge-settings: 10 assertions passed"
exit 0
