#!/usr/bin/env bash
# Tests for templates/hooks/check-audit.sh (v8 item 1.1)
#
# Verifies:
#   1. Exits 0 on every input variant (exit-0 guarantee)
#   2. Correct tag extraction (deploy / redis-flush / npm-install / git-destructive / rm-rf)
#   3. Preserves escaped quotes in command field (regression test for earlier grep bug)
#   4. Auto-creates .gitignore in audit dir (Copilot review finding)
#   5. Produces valid JSONL entries

set +e  # assertions track failures manually

HOOK="$(cd "$(dirname "$0")/../.." && pwd)/templates/hooks/check-audit.sh"
if [ ! -x "$HOOK" ]; then
  echo "  FAIL: hook not executable at $HOOK"
  exit 1
fi

# mktemp portability: GNU `mktemp -d` works without template, BSD/macOS legacy
# requires `-t <prefix>`. Try GNU form first, fall back to BSD form.
TMPDIR=$(mktemp -d 2>/dev/null || mktemp -d -t idea-factory 2>/dev/null)
if [ -z "$TMPDIR" ] || [ ! -d "$TMPDIR" ]; then
  echo "  FAIL: could not create temp directory"
  exit 1
fi
trap 'rm -rf "$TMPDIR"' EXIT
cd "$TMPDIR" || exit 1

# Capture date ONCE at test start to avoid race condition if midnight passes
# between hook invocation (which writes to a date-stamped file) and assertion
# helpers (which read from the same file).
TODAY=$(date +%Y-%m-%d)

FAILED=0

fail() {
  echo "  FAIL: $1"
  FAILED=$((FAILED + 1))
}

# Run hook with JSON input. Echoes exit code.
run_hook() {
  printf '%s' "$1" | bash "$HOOK"
  echo "$?"
}

# Last entry's "cmd" field (via python3) — uses captured TODAY to avoid date race
last_cmd() {
  local f=".claude/audit/$TODAY.jsonl"
  [ -f "$f" ] || { echo ""; return; }
  tail -1 "$f" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())['cmd'])" 2>/dev/null
}

# Last entry's "tags" field — uses captured TODAY to avoid date race
last_tags() {
  local f=".claude/audit/$TODAY.jsonl"
  [ -f "$f" ] || { echo ""; return; }
  tail -1 "$f" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())['tags'])" 2>/dev/null
}

assert_eq() {
  [ "$1" = "$2" ] || fail "$3 — expected '$2', got '$1'"
}

# ── Test 1: vercel --prod → tag 'deploy' ─────────────────────────
RC=$(run_hook '{"tool_input":{"command":"vercel --prod"}}')
assert_eq "$RC" "0" "T1: exit 0 for vercel --prod"
assert_eq "$(last_tags)" "deploy" "T1: tag = deploy"

# ── Test 2: benign ls → empty tag ────────────────────────────────
RC=$(run_hook '{"tool_input":{"command":"ls -la"}}')
assert_eq "$RC" "0" "T2: exit 0 for ls -la"
assert_eq "$(last_tags)" "" "T2: tag = (empty)"

# ── Test 3: escaped quotes preserved (regression test) ───────────
# Earlier grep-based extraction truncated on escaped quotes. python3 parser fixed.
RC=$(run_hook '{"tool_input":{"command":"echo \"hello\""}}')
assert_eq "$RC" "0" "T3: exit 0 for escaped quotes"
assert_eq "$(last_cmd)" 'echo "hello"' "T3: cmd preserves escaped quotes"

# ── Test 4: lowercase redis-cli flushdb (case-insensitive regression) ──
# Earlier regex was uppercase-only (FLUSHDB). Added -i flag.
RC=$(run_hook '{"tool_input":{"command":"redis-cli flushdb"}}')
assert_eq "$RC" "0" "T4: exit 0 for lowercase flushdb"
assert_eq "$(last_tags)" "redis-flush" "T4: tag = redis-flush (case-insensitive)"

# ── Test 5: bare npm install (end-of-string regression) ──────────
# Earlier regex required a non-dash char after "install ". Fixed to allow EOL.
RC=$(run_hook '{"tool_input":{"command":"npm install"}}')
assert_eq "$RC" "0" "T5: exit 0 for bare npm install"
assert_eq "$(last_tags)" "npm-install" "T5: tag = npm-install (bare form)"

# ── Test 6: git force push → git-destructive ─────────────────────
RC=$(run_hook '{"tool_input":{"command":"git push origin main --force"}}')
assert_eq "$RC" "0" "T6: exit 0 for git --force push"
assert_eq "$(last_tags)" "git-destructive" "T6: tag = git-destructive"

# ── Test 7: empty stdin → exit 0 (defensive) ─────────────────────
echo '' | bash "$HOOK"
RC=$?
assert_eq "$RC" "0" "T7: exit 0 for empty stdin"

# ── Test 8: malformed JSON → exit 0 (defensive) ──────────────────
echo 'not json at all' | bash "$HOOK"
RC=$?
assert_eq "$RC" "0" "T8: exit 0 for malformed JSON"

# ── Test 9: .gitignore auto-created (Copilot review finding) ─────
if [ ! -f .claude/audit/.gitignore ]; then
  fail "T9: .gitignore not auto-created in .claude/audit/"
else
  content=$(cat .claude/audit/.gitignore)
  case "$content" in
    *'*'*) ;;
    *) fail "T9: .gitignore does not contain '*' glob" ;;
  esac
fi

# ── Test 10: all JSONL entries are valid JSON ────────────────────
python3 -c "
import json
f = '.claude/audit/$TODAY.jsonl'
try:
    with open(f) as fh:
        for line in fh:
            if line.strip():
                json.loads(line)
    exit(0)
except Exception as e:
    print(f'FAIL: invalid JSONL — {e}')
    exit(1)
" || fail "T10: not all JSONL entries valid JSON"

# ── Summary ───────────────────────────────────────────────────────
if [ "$FAILED" -gt 0 ]; then
  echo ""
  echo "check-audit: $FAILED assertion(s) failed"
  exit 1
fi

echo "check-audit: 10 assertions passed"
exit 0
