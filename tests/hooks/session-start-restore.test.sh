#!/usr/bin/env bash
# Tests for templates/hooks/session-start-restore.sh (v8 item 7.1)
#
# Verifies:
#   1. Exits 0 when no state directory exists
#   2. Exits 0 when state directory is empty
#   3. Exits 0 when only stale (>24h) files exist — emits nothing
#   4. Detects a recent state file and emits a system-reminder hint
#   5. Emits file path in the hint
#   6. Emits session phase in the hint (when present)
#   7. Emits working files in the hint (when present)
#   8. Emits summary in the hint (when present)
#   9. Exits 0 on malformed state file
#  10. Exits 0 on empty stdin

set +e  # assertions track failures manually

HOOK="$(cd "$(dirname "$0")/../.." && pwd)/templates/hooks/session-start-restore.sh"
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

assert_contains() {
  case "$1" in
    *"$2"*) ;;
    *) fail "$3 — expected '$1' to contain '$2'" ;;
  esac
}

assert_empty() {
  [ -z "$1" ] || fail "$2 — expected empty output, got '$1'"
}

# Run hook, capture stdout, return exit code via subshell
run_hook() {
  export CLAUDE_STATE_DIR="${1:-.claude/state}"
  OUT=$(bash "$HOOK" 2>/dev/null)
  RC=$?
  echo "$RC|$OUT"
}

# ── Test 1: no state directory → exit 0, no output ───────────────
RESULT=$(CLAUDE_STATE_DIR=".claude/state-nonexistent" bash "$HOOK" 2>/dev/null; echo "RC=$?")
RC=$(echo "$RESULT" | grep "RC=" | sed 's/RC=//')
assert_eq "$RC" "0" "T1: exit 0 when no state dir"
OUT=$(echo "$RESULT" | grep -v "RC=")
assert_empty "$OUT" "T1: no output when no state dir"

# ── Test 2: state dir exists but empty → exit 0, no output ───────
mkdir -p .claude/state
RESULT=$(CLAUDE_STATE_DIR=".claude/state" bash "$HOOK" 2>/dev/null; echo "RC=$?")
RC=$(echo "$RESULT" | grep "RC=" | sed 's/RC=//')
assert_eq "$RC" "0" "T2: exit 0 when state dir empty"
OUT=$(echo "$RESULT" | grep -v "RC=")
assert_empty "$OUT" "T2: no output when no state files"

# ── Test 3: stale file (>24h old) → exit 0, no output ────────────
STALE_FILE=".claude/state/session-2000-01-01-00-00.json"
python3 -c "
import json
state = {'ts':'2000-01-01T00:00:00Z','session_id':'old','phase':'MVP','working_files':[],'summary':'old session'}
with open('$STALE_FILE','w') as fh:
    json.dump(state, fh)
" 2>/dev/null
# Touch to make it 25 hours old
python3 -c "
import os, time
os.utime('$STALE_FILE', (time.time() - 90001, time.time() - 90001))
" 2>/dev/null
RESULT=$(CLAUDE_STATE_DIR=".claude/state" bash "$HOOK" 2>/dev/null; echo "RC=$?")
RC=$(echo "$RESULT" | grep "RC=" | sed 's/RC=//')
assert_eq "$RC" "0" "T3: exit 0 for stale file"
OUT=$(echo "$RESULT" | grep -v "RC=")
assert_empty "$OUT" "T3: no output for stale file (>24h)"

# ── Test 4: recent file → emits hint with file path ──────────────
RECENT_FILE=".claude/state/session-2026-04-13-10-00.json"
python3 -c "
import json
state = {
    'ts':'2026-04-13T10:00:00Z',
    'session_id':'sess-xyz',
    'phase':'Harden',
    'working_files':['src/app.ts','src/utils.ts'],
    'summary':'Fixed auth bug, added rate limiting'
}
with open('$RECENT_FILE','w') as fh:
    json.dump(state, fh)
" 2>/dev/null
OUT=$(CLAUDE_STATE_DIR=".claude/state" bash "$HOOK" 2>/dev/null)
RC=$?
assert_eq "$RC" "0" "T4: exit 0 for recent file"
assert_contains "$OUT" "$RECENT_FILE" "T4: hint contains file path"

# ── Test 5: hint contains phase ───────────────────────────────────
assert_contains "$OUT" "Harden" "T5: hint contains phase"

# ── Test 6: hint contains working files ───────────────────────────
assert_contains "$OUT" "src/app.ts" "T6: hint contains working files"

# ── Test 7: hint contains summary ─────────────────────────────────
assert_contains "$OUT" "Fixed auth bug" "T7: hint contains summary"

# ── Test 8: hint contains timestamp ───────────────────────────────
assert_contains "$OUT" "2026-04-13" "T8: hint contains timestamp"

# ── Test 9: malformed state file → exit 0 ─────────────────────────
# Use a fresh temp dir so malformed file is the only candidate
TMPDIR2=$(mktemp -d 2>/dev/null || mktemp -d -t idea-factory2 2>/dev/null)
BAD_FILE="$TMPDIR2/session-2026-04-13-11-00.json"
printf 'not valid json' > "$BAD_FILE"
CLAUDE_STATE_DIR="$TMPDIR2" bash "$HOOK" 2>/dev/null
RC=$?
assert_eq "$RC" "0" "T9: exit 0 for malformed state file"
rm -rf "$TMPDIR2"

# ── Test 10: empty stdin → exit 0 ────────────────────────────────
TMPDIR3=$(mktemp -d 2>/dev/null || mktemp -d -t idea-factory3 2>/dev/null)
echo '' | CLAUDE_STATE_DIR="$TMPDIR3" bash "$HOOK" 2>/dev/null
RC=$?
assert_eq "$RC" "0" "T10: exit 0 with empty stdin"
rm -rf "$TMPDIR3"

# ── Summary ───────────────────────────────────────────────────────
if [ "$FAILED" -gt 0 ]; then
  echo ""
  echo "session-start-restore: $FAILED assertion(s) failed"
  exit 1
fi

echo "session-start-restore: 10 assertions passed"
exit 0
