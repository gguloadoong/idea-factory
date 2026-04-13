#!/usr/bin/env bash
# Tests for templates/hooks/pre-compact-save.sh (v8 item 7.1)
#
# Verifies:
#   1. Exits 0 on normal payload
#   2. Exits 0 on empty stdin
#   3. Exits 0 on malformed JSON
#   4. Creates .claude/state/ directory automatically
#   5. Creates .gitignore in state dir on first run
#   6. Output file is valid JSON
#   7. Output contains expected fields (ts, session_id, phase, working_files, summary)
#   8. session_id extracted from payload
#   9. summary extracted from payload
#  10. Runs in a directory without git (no crash)

set +e  # assertions track failures manually

HOOK="$(cd "$(dirname "$0")/../.." && pwd)/templates/hooks/pre-compact-save.sh"
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

# Run hook with given stdin payload, return exit code
run_hook() {
  printf '%s' "$1" | bash "$HOOK"
  echo "$?"
}

# Find the most recently created session-*.json file in .claude/state/
latest_state_file() {
  ls -t .claude/state/session-*.json 2>/dev/null | head -1
}

# Read a field from the latest state file via python3
state_field() {
  local f
  f=$(latest_state_file)
  [ -z "$f" ] && { echo ""; return; }
  python3 -c "
import json, sys
with open('$f') as fh:
    d = json.load(fh)
val = d.get('$1', '')
if isinstance(val, list):
    print(','.join(str(v) for v in val))
else:
    print(val)
" 2>/dev/null
}

# ── Test 1: Normal payload → exit 0 ─────────────────────────────
RC=$(run_hook '{"session_id":"test-session-abc","summary":"MVP phase complete"}')
assert_eq "$RC" "0" "T1: exit 0 for normal payload"

# ── Test 2: State directory auto-created ─────────────────────────
if [ ! -d ".claude/state" ]; then
  fail "T2: .claude/state/ not auto-created"
else
  echo "  ok T2: .claude/state/ auto-created"
fi

# ── Test 3: State file created ───────────────────────────────────
STATE_FILE=$(latest_state_file)
if [ -z "$STATE_FILE" ]; then
  fail "T3: no session-*.json file found in .claude/state/"
else
  echo "  ok T3: state file created at $STATE_FILE"
fi

# ── Test 4: State file is valid JSON ─────────────────────────────
python3 -c "
import json
f = '$(latest_state_file)'
try:
    with open(f) as fh:
        json.load(fh)
    exit(0)
except Exception as e:
    print(f'invalid JSON: {e}')
    exit(1)
" 2>/dev/null || fail "T4: state file is not valid JSON"

# ── Test 5: session_id extracted from payload ─────────────────────
SID=$(state_field "session_id")
assert_eq "$SID" "test-session-abc" "T5: session_id extracted"

# ── Test 6: summary extracted from payload ────────────────────────
SUMMARY=$(state_field "summary")
assert_eq "$SUMMARY" "MVP phase complete" "T6: summary extracted"

# ── Test 7: required fields present ──────────────────────────────
for field in ts session_id phase working_files summary; do
  python3 -c "
import json
f = '$(latest_state_file)'
with open(f) as fh:
    d = json.load(fh)
assert '$field' in d, 'missing field: $field'
" 2>/dev/null || fail "T7: required field '$field' missing from state file"
done
echo "  ok T7: all required fields present (ts, session_id, phase, working_files, summary)"

# ── Test 8: .gitignore auto-created ──────────────────────────────
if [ ! -f ".claude/state/.gitignore" ]; then
  fail "T8: .gitignore not auto-created in .claude/state/"
else
  content=$(cat .claude/state/.gitignore)
  case "$content" in
    *'*'*) echo "  ok T8: .gitignore contains '*' glob" ;;
    *) fail "T8: .gitignore does not contain '*' glob" ;;
  esac
fi

# ── Test 9: empty stdin → exit 0 ─────────────────────────────────
RC=$(echo '' | bash "$HOOK"; echo "$?")
assert_eq "$RC" "0" "T9: exit 0 for empty stdin"

# ── Test 10: malformed JSON → exit 0 ─────────────────────────────
RC=$(echo 'not json at all' | bash "$HOOK"; echo "$?")
assert_eq "$RC" "0" "T10: exit 0 for malformed JSON"

# ── Summary ───────────────────────────────────────────────────────
if [ "$FAILED" -gt 0 ]; then
  echo ""
  echo "pre-compact-save: $FAILED assertion(s) failed"
  exit 1
fi

echo "pre-compact-save: 10 assertions passed"
exit 0
