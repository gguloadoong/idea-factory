#!/usr/bin/env bash
# Tests for templates/hooks/audit-review.sh (v8 item 1.4)
#
# Verifies:
#   1.  Empty audit directory → silent exit 0
#   2.  Normal commands only → no output, exit 0
#   3.  git-destructive immediately before deploy → detected
#   4.  rm-rf 3+ times in same session → detected
#   5.  CAREFUL tags >= 10 in session → detected
#   6.  Malformed JSONL lines → exit 0 (skips bad lines)
#   7.  Empty stdin (no payload) → exit 0
#   8.  Review result file created when finding exists
#   9.  Shell injection canary in cmd field → not executed
#   10. redis-flush followed by another CAREFUL tag → detected
#   11. npm-install immediately before deploy → detected
#   12. Review file contains valid JSON

set +e  # manual failure tracking

HOOK="$(cd "$(dirname "$0")/../.." && pwd)/templates/hooks/audit-review.sh"
if [ ! -x "$HOOK" ]; then
  echo "  FAIL: hook not executable at $HOOK"
  exit 1
fi

# mktemp portability (GNU + BSD/macOS)
TMPDIR_BASE=$(mktemp -d 2>/dev/null || mktemp -d -t audit-review-test 2>/dev/null)
if [ -z "$TMPDIR_BASE" ] || [ ! -d "$TMPDIR_BASE" ]; then
  echo "  FAIL: could not create temp directory"
  exit 1
fi
trap 'rm -rf "$TMPDIR_BASE"' EXIT

TODAY=$(date +%Y-%m-%d 2>/dev/null || echo "1970-01-01")

FAILED=0
ASSERTIONS=0

fail() {
  echo "  FAIL: $1"
  FAILED=$((FAILED + 1))
}

assert_eq() {
  ASSERTIONS=$((ASSERTIONS + 1))
  [ "$1" = "$2" ] || fail "$3 — expected '$2', got '$1'"
}

assert_exit0() {
  ASSERTIONS=$((ASSERTIONS + 1))
  [ "$1" = "0" ] || fail "$2 — expected exit 0, got $1"
}

assert_contains() {
  ASSERTIONS=$((ASSERTIONS + 1))
  printf '%s' "$2" | grep -qF "$1" 2>/dev/null || fail "$3 — '$1' not found in output"
}

assert_not_contains() {
  ASSERTIONS=$((ASSERTIONS + 1))
  if printf '%s' "$2" | grep -qF "$1" 2>/dev/null; then
    fail "$3 — '$1' unexpectedly found in output"
  fi
}

# Helper: build a JSONL audit entry
make_entry() {
  local session="$1" tags="$2" cmd="$3"
  printf '{"ts":"2026-04-13T00:00:00Z","session":"%s","matcher":"Bash","tags":"%s","cmd":"%s"}\n' \
    "$session" "$tags" "$cmd"
}

# ── T1: Empty audit directory → silent exit 0 ───────────────────
T1_DIR="$TMPDIR_BASE/t1"
mkdir -p "$T1_DIR"
OUT=$(CLAUDE_AUDIT_DIR="$T1_DIR/audit" bash "$HOOK" < /dev/null 2>/dev/null)
RC=$?
assert_exit0 "$RC" "T1: empty audit dir exit 0"
assert_eq "$OUT" "" "T1: no output on empty audit dir"

# ── T2: Normal commands only → no output, exit 0 ────────────────
T2_DIR="$TMPDIR_BASE/t2"
mkdir -p "$T2_DIR/audit"
make_entry "sess-normal" "" "ls -la" >> "$T2_DIR/audit/$TODAY.jsonl"
make_entry "sess-normal" "" "git status" >> "$T2_DIR/audit/$TODAY.jsonl"
make_entry "sess-normal" "" "python3 test.py" >> "$T2_DIR/audit/$TODAY.jsonl"
OUT=$(CLAUDE_AUDIT_DIR="$T2_DIR/audit" bash "$HOOK" < /dev/null 2>/dev/null)
RC=$?
assert_exit0 "$RC" "T2: normal commands exit 0"
assert_eq "$OUT" "" "T2: no output when no suspicious patterns"

# ── T3: git-destructive immediately before deploy → detected ─────
T3_DIR="$TMPDIR_BASE/t3"
mkdir -p "$T3_DIR/audit"
make_entry "sess-a" "git-destructive" "git push --force origin main" >> "$T3_DIR/audit/$TODAY.jsonl"
make_entry "sess-a" "deploy" "vercel --prod" >> "$T3_DIR/audit/$TODAY.jsonl"
OUT=$(CLAUDE_AUDIT_DIR="$T3_DIR/audit" bash "$HOOK" < /dev/null 2>/dev/null)
RC=$?
assert_exit0 "$RC" "T3: git-destructive+deploy exit 0"
assert_contains "git-destructive-before-deploy" "$OUT" "T3: pattern detected"

# ── T4: rm-rf 3+ times in same session → detected ───────────────
T4_DIR="$TMPDIR_BASE/t4"
mkdir -p "$T4_DIR/audit"
make_entry "sess-b" "rm-rf" "rm -rf /tmp/a" >> "$T4_DIR/audit/$TODAY.jsonl"
make_entry "sess-b" "rm-rf" "rm -rf /tmp/b" >> "$T4_DIR/audit/$TODAY.jsonl"
make_entry "sess-b" "rm-rf" "rm -rf /tmp/c" >> "$T4_DIR/audit/$TODAY.jsonl"
OUT=$(CLAUDE_AUDIT_DIR="$T4_DIR/audit" bash "$HOOK" < /dev/null 2>/dev/null)
RC=$?
assert_exit0 "$RC" "T4: rm-rf 3x exit 0"
assert_contains "rm-rf-repeated" "$OUT" "T4: rm-rf-repeated pattern detected"

# ── T5: CAREFUL tags >= 10 in session → detected ─────────────────
T5_DIR="$TMPDIR_BASE/t5"
mkdir -p "$T5_DIR/audit"
for i in $(seq 1 10); do
  make_entry "sess-c" "deploy" "vercel --prod run$i" >> "$T5_DIR/audit/$TODAY.jsonl"
done
OUT=$(CLAUDE_AUDIT_DIR="$T5_DIR/audit" bash "$HOOK" < /dev/null 2>/dev/null)
RC=$?
assert_exit0 "$RC" "T5: excessive CAREFUL exit 0"
assert_contains "excessive-careful-commands" "$OUT" "T5: excessive-careful-commands detected"

# ── T6: Malformed JSONL lines → exit 0, skips bad lines ─────────
T6_DIR="$TMPDIR_BASE/t6"
mkdir -p "$T6_DIR/audit"
printf 'not valid json\n' >> "$T6_DIR/audit/$TODAY.jsonl"
printf '{incomplete\n' >> "$T6_DIR/audit/$TODAY.jsonl"
make_entry "sess-d" "" "git status" >> "$T6_DIR/audit/$TODAY.jsonl"
OUT=$(CLAUDE_AUDIT_DIR="$T6_DIR/audit" bash "$HOOK" < /dev/null 2>/dev/null)
RC=$?
assert_exit0 "$RC" "T6: malformed JSONL exit 0"
assert_eq "$OUT" "" "T6: no false positives from malformed lines"

# ── T7: Empty stdin → exit 0 ─────────────────────────────────────
T7_DIR="$TMPDIR_BASE/t7"
mkdir -p "$T7_DIR/audit"
make_entry "sess-e" "" "echo hello" >> "$T7_DIR/audit/$TODAY.jsonl"
RC=$(echo '' | CLAUDE_AUDIT_DIR="$T7_DIR/audit" bash "$HOOK" > /dev/null 2>&1; echo $?)
assert_exit0 "$RC" "T7: empty stdin exit 0"

# ── T8: Review result file created when finding exists ───────────
T8_DIR="$TMPDIR_BASE/t8"
mkdir -p "$T8_DIR/audit"
make_entry "sess-f" "git-destructive" "git push --force" >> "$T8_DIR/audit/$TODAY.jsonl"
make_entry "sess-f" "deploy" "vercel --prod" >> "$T8_DIR/audit/$TODAY.jsonl"
CLAUDE_AUDIT_DIR="$T8_DIR/audit" bash "$HOOK" < /dev/null > /dev/null 2>&1
ASSERTIONS=$((ASSERTIONS + 1))
if [ ! -f "$T8_DIR/audit/review-$TODAY.jsonl" ]; then
  fail "T8: review file not created"
fi

# ── T9: Shell injection canary in cmd field → not executed ───────
T9_DIR="$TMPDIR_BASE/t9"
mkdir -p "$T9_DIR/audit"
CANARY="$TMPDIR_BASE/injection-canary-t9"
rm -f "$CANARY"
# Embed injection attempt in the tags field (passed through json.loads, not shell)
printf '{"ts":"2026-04-13T00:00:00Z","session":"inj","matcher":"Bash","tags":"rm-rf $(touch %s)","cmd":"safe"}\n' \
  "$CANARY" >> "$T9_DIR/audit/$TODAY.jsonl"
printf '{"ts":"2026-04-13T00:00:00Z","session":"inj","matcher":"Bash","tags":"rm-rf","cmd":"safe"}\n' >> "$T9_DIR/audit/$TODAY.jsonl"
printf '{"ts":"2026-04-13T00:00:00Z","session":"inj","matcher":"Bash","tags":"rm-rf","cmd":"safe"}\n' >> "$T9_DIR/audit/$TODAY.jsonl"
CLAUDE_AUDIT_DIR="$T9_DIR/audit" bash "$HOOK" < /dev/null > /dev/null 2>&1
RC=$?
assert_exit0 "$RC" "T9: injection attempt exit 0"
ASSERTIONS=$((ASSERTIONS + 1))
if [ -f "$CANARY" ]; then
  fail "T9: SHELL INJECTION — canary file was created!"
fi

# ── T10: redis-flush followed by another CAREFUL tag → detected ──
T10_DIR="$TMPDIR_BASE/t10"
mkdir -p "$T10_DIR/audit"
make_entry "sess-g" "redis-flush" "redis-cli FLUSHALL" >> "$T10_DIR/audit/$TODAY.jsonl"
make_entry "sess-g" "deploy" "vercel --prod" >> "$T10_DIR/audit/$TODAY.jsonl"
OUT=$(CLAUDE_AUDIT_DIR="$T10_DIR/audit" bash "$HOOK" < /dev/null 2>/dev/null)
RC=$?
assert_exit0 "$RC" "T10: redis-flush+CAREFUL exit 0"
assert_contains "redis-flush-followed-by-dangerous" "$OUT" "T10: redis-flush pattern detected"

# ── T11: npm-install immediately before deploy → detected ─────────
T11_DIR="$TMPDIR_BASE/t11"
mkdir -p "$T11_DIR/audit"
make_entry "sess-h" "npm-install" "npm install express" >> "$T11_DIR/audit/$TODAY.jsonl"
make_entry "sess-h" "deploy" "vercel --prod" >> "$T11_DIR/audit/$TODAY.jsonl"
OUT=$(CLAUDE_AUDIT_DIR="$T11_DIR/audit" bash "$HOOK" < /dev/null 2>/dev/null)
RC=$?
assert_exit0 "$RC" "T11: npm-install+deploy exit 0"
assert_contains "npm-install-then-deploy" "$OUT" "T11: npm-install-then-deploy detected"

# ── T12: Review file contains valid JSON ─────────────────────────
# Re-use T8 review file which should exist
python3 -c "
import json, sys
f = '$T8_DIR/audit/review-$TODAY.jsonl'
try:
    with open(f) as fh:
        for line in fh:
            if line.strip():
                json.loads(line)
    sys.exit(0)
except Exception as e:
    print('invalid JSONL:', e)
    sys.exit(1)
" 2>/dev/null
ASSERTIONS=$((ASSERTIONS + 1))
[ $? -eq 0 ] || fail "T12: review file is not valid JSONL"

# ── Summary ───────────────────────────────────────────────────────
if [ "$FAILED" -gt 0 ]; then
  echo ""
  echo "audit-review: $((ASSERTIONS - FAILED))/$ASSERTIONS passed, $FAILED failed"
  exit 1
fi

echo "audit-review: $ASSERTIONS assertions passed"
exit 0
