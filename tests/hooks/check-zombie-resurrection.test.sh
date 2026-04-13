#!/usr/bin/env bash
# Tests for templates/hooks/check-zombie-resurrection.sh (v8 item 3.3)
#
# Verifies:
#   1. Exits 0 on every input variant
#   2. Detects zombie file (deleted file recreated)
#   3. Detects resurrected symbols from deleted history
#   4. No false positive for clean files with no deletion history
#   5. git repo가 아닌 곳에서 graceful exit 0
#   6. Empty stdin → exit 0
#   7. Malformed JSON → exit 0
#   8. .gitignore auto-created in audit dir
#   9. All JSONL entries valid JSON
#  10. Shell injection canary — file_path injection does not execute
#  11. Missing tool_input → exit 0
#  12. Missing file_path → exit 0

set +e

HOOK="$(cd "$(dirname "$0")/../.." && pwd)/templates/hooks/check-zombie-resurrection.sh"
if [ ! -x "$HOOK" ]; then
  echo "  FAIL: hook not executable at $HOOK"
  exit 1
fi

# mktemp portability (GNU + BSD/macOS)
TMPDIR=$(mktemp -d 2>/dev/null || mktemp -d -t idea-factory 2>/dev/null)
if [ -z "$TMPDIR" ] || [ ! -d "$TMPDIR" ]; then
  echo "  FAIL: could not create temp directory"
  exit 1
fi
trap 'rm -rf "$TMPDIR"' EXIT

TODAY=$(date +%Y-%m-%d)
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

# Helper: read last log entry field from a given log file
last_field_from() {
  local logfile="$1"
  local field="$2"
  [ -f "$logfile" ] || { echo ""; return; }
  tail -1 "$logfile" | python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read())
    v = d.get('$field', '')
    if isinstance(v, list):
        print(','.join(str(x) for x in v))
    elif isinstance(v, bool):
        print('true' if v else 'false')
    else:
        print(v)
except Exception:
    print('')
" 2>/dev/null
}

count_log_lines() {
  local f="$1"
  if [ -f "$f" ]; then
    wc -l < "$f" | tr -d ' '
  else
    echo "0"
  fi
}

# ─────────────────────────────────────────────────────────────────────
# Set up a real git repo for the tests that need git history
# ─────────────────────────────────────────────────────────────────────
REPO="$TMPDIR/testrepo"
mkdir -p "$REPO"
cd "$REPO" || exit 1

git init -q
git config user.email "test@example.com"
git config user.name "Test"

# Audit dir inside the repo so hook can find it
AUDIT_DIR="$REPO/.claude/audit"
export CLAUDE_AUDIT_DIR="$AUDIT_DIR"
mkdir -p "$AUDIT_DIR"
LOG_FILE="$AUDIT_DIR/zombie-$TODAY.jsonl"

# ── Baseline commit: add a regular file ──────────────────────────
mkdir -p src
cat > src/utils.js <<'EOF'
function helperOne(x) { return x + 1; }
function helperTwo(x) { return x * 2; }
const CONFIG = { debug: false };
EOF
git add src/utils.js
git commit -q -m "init: add utils"

# ── Commit that DELETES utils.js ─────────────────────────────────
git rm -q src/utils.js
git commit -q -m "remove: delete utils.js"

# ─────────────────────────────────────────────────────────────────────
# T1: Zombie file detection — deleted file recreated → log entry emitted
# ─────────────────────────────────────────────────────────────────────
mkdir -p "$REPO/src"
cat > "$REPO/src/utils.js" <<'EOF'
function helperOne(x) { return x + 1; }
EOF
PAYLOAD="{\"tool_input\":{\"file_path\":\"$REPO/src/utils.js\"}}"
OUT=$(printf '%s' "$PAYLOAD" | bash "$HOOK")
RC=$?
assert_exit0 "$RC" "T1: exit 0 on zombie file"
ASSERTIONS=$((ASSERTIONS + 1))
if [ "$(count_log_lines "$LOG_FILE")" -lt "1" ]; then
  fail "T1: expected log entry for zombie file recreation"
fi
ZOMBIE_FIELD=$(last_field_from "$LOG_FILE" "zombie_file")
if [ "$ZOMBIE_FIELD" != "true" ]; then
  fail "T1: zombie_file should be true, got '$ZOMBIE_FIELD'"
fi
ASSERTIONS=$((ASSERTIONS + 1))

# ─────────────────────────────────────────────────────────────────────
# T2: Resurrected symbol detection — function from deleted file reappears
# ─────────────────────────────────────────────────────────────────────
BEFORE=$(count_log_lines "$LOG_FILE")
# helperTwo was in the deleted utils.js; recreated file has helperTwo
mkdir -p "$REPO/src"
cat > "$REPO/src/utils.js" <<'EOF'
function helperTwo(x) { return x * 2; }
EOF
PAYLOAD="{\"tool_input\":{\"file_path\":\"$REPO/src/utils.js\"}}"
printf '%s' "$PAYLOAD" | bash "$HOOK" >/dev/null
RC=$?
assert_exit0 "$RC" "T2: exit 0 on symbol resurrection"
AFTER=$(count_log_lines "$LOG_FILE")
ASSERTIONS=$((ASSERTIONS + 1))
if [ "$AFTER" -le "$BEFORE" ]; then
  fail "T2: expected new log entry for resurrected symbol"
fi
SYMS=$(last_field_from "$LOG_FILE" "resurrected_symbols")
case "$SYMS" in
  *helperTwo*) ;;
  *) fail "T2: resurrected_symbols should contain helperTwo, got '$SYMS'" ;;
esac
ASSERTIONS=$((ASSERTIONS + 1))

# ─────────────────────────────────────────────────────────────────────
# T3: Clean file with no deletion history → no log entry (no false positive)
# ─────────────────────────────────────────────────────────────────────
mkdir -p "$REPO/src"
cat > "$REPO/src/brand-new.js" <<'EOF'
function freshFunction(x) { return x; }
EOF
(cd "$REPO" && git add src/brand-new.js && git commit -q -m "add: brand-new.js") 2>/dev/null || true

BEFORE=$(count_log_lines "$LOG_FILE")
PAYLOAD="{\"tool_input\":{\"file_path\":\"$REPO/src/brand-new.js\"}}"
printf '%s' "$PAYLOAD" | bash "$HOOK" >/dev/null
RC=$?
assert_exit0 "$RC" "T3: exit 0 on clean file"
AFTER=$(count_log_lines "$LOG_FILE")
assert_eq "$BEFORE" "$AFTER" "T3: no false positive for file with no deletion history"

# ─────────────────────────────────────────────────────────────────────
# T4: Non-git directory → graceful exit 0
# ─────────────────────────────────────────────────────────────────────
NONGIT="$TMPDIR/nongit"
mkdir -p "$NONGIT"
cat > "$NONGIT/somefile.js" <<'EOF'
function foo() {}
EOF
PAYLOAD="{\"tool_input\":{\"file_path\":\"$NONGIT/somefile.js\"}}"
printf '%s' "$PAYLOAD" | bash "$HOOK" >/dev/null
RC=$?
assert_exit0 "$RC" "T4: exit 0 when not in a git repo"

# ─────────────────────────────────────────────────────────────────────
# T5: Empty stdin → exit 0
# ─────────────────────────────────────────────────────────────────────
echo '' | bash "$HOOK" >/dev/null
RC=$?
assert_exit0 "$RC" "T5: exit 0 with empty stdin"

# ─────────────────────────────────────────────────────────────────────
# T6: Malformed JSON → exit 0
# ─────────────────────────────────────────────────────────────────────
echo 'not valid json }{' | bash "$HOOK" >/dev/null
RC=$?
assert_exit0 "$RC" "T6: exit 0 with malformed JSON"

# ─────────────────────────────────────────────────────────────────────
# T7: Missing tool_input field → exit 0
# ─────────────────────────────────────────────────────────────────────
printf '%s' '{}' | bash "$HOOK" >/dev/null
RC=$?
assert_exit0 "$RC" "T7: exit 0 with missing tool_input"

# ─────────────────────────────────────────────────────────────────────
# T8: Missing file_path → exit 0
# ─────────────────────────────────────────────────────────────────────
printf '%s' '{"tool_input":{}}' | bash "$HOOK" >/dev/null
RC=$?
assert_exit0 "$RC" "T8: exit 0 with missing file_path"

# ─────────────────────────────────────────────────────────────────────
# T9: .gitignore auto-created in audit dir
# ─────────────────────────────────────────────────────────────────────
if [ ! -f "$AUDIT_DIR/.gitignore" ]; then
  fail "T9: .gitignore not auto-created in audit dir"
fi
ASSERTIONS=$((ASSERTIONS + 1))

# ─────────────────────────────────────────────────────────────────────
# T10: All JSONL entries valid JSON
# ─────────────────────────────────────────────────────────────────────
python3 -c "
import json
f = '$LOG_FILE'
try:
    with open(f) as fh:
        for i, line in enumerate(fh, 1):
            if line.strip():
                json.loads(line)
except FileNotFoundError:
    pass  # No log = no bad entries, fine
except Exception as e:
    print(f'FAIL: invalid JSONL at line {i}: {e}')
    exit(1)
" || fail "T10: not all JSONL entries are valid JSON"
ASSERTIONS=$((ASSERTIONS + 1))

# ─────────────────────────────────────────────────────────────────────
# T11: Shell injection canary — file_path with $(...) does not execute
# ─────────────────────────────────────────────────────────────────────
CANARY="$TMPDIR/injection-canary"
rm -f "$CANARY"
PAYLOAD="{\"tool_input\":{\"file_path\":\"$TMPDIR/\$(touch $CANARY).js\"}}"
printf '%s' "$PAYLOAD" | bash "$HOOK" >/dev/null
RC=$?
assert_exit0 "$RC" "T11: exit 0 with injection-pattern path"
if [ -f "$CANARY" ]; then
  fail "T11: SHELL INJECTION — canary file was created!"
fi
ASSERTIONS=$((ASSERTIONS + 1))

# ─────────────────────────────────────────────────────────────────────
# T12: Severity field is 'high' for zombie file
# ─────────────────────────────────────────────────────────────────────
# Re-read the very first T1 entry (line 1 of log file)
SEV=$(head -1 "$LOG_FILE" | python3 -c "
import json,sys
try:
    d=json.loads(sys.stdin.read())
    print(d.get('severity',''))
except Exception:
    print('')
" 2>/dev/null)
if [ "$SEV" != "high" ]; then
  fail "T12: severity should be 'high' for zombie file, got '$SEV'"
fi
ASSERTIONS=$((ASSERTIONS + 1))

# ─────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────
if [ "$FAILED" -gt 0 ]; then
  echo ""
  echo "check-zombie-resurrection: $((ASSERTIONS - FAILED))/$ASSERTIONS passed, $FAILED failed"
  exit 1
fi

echo "check-zombie-resurrection: $ASSERTIONS assertions passed"
exit 0
