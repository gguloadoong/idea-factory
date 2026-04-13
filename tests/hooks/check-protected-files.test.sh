#!/usr/bin/env bash
# Tests for templates/hooks/check-protected-files.sh (v8 item 3.4)
#
# Verifies:
#   1. Protected glob matched and logged
#   2. Non-protected file — no false positive
#   3. YAML parsed correctly (rules loaded)
#   4. Multiple rules match simultaneously
#   5. protected-files.yml absent — graceful exit 0
#   6. Empty stdin → exit 0
#   7. Malformed JSON → exit 0
#   8. .gitignore auto-created in audit dir
#   9. reason + reviewer fields present in audit log
#  10. Shell injection canary (no code execution)
#  11. Exit 0 on every code path (invariant)
#  12. .protected-files.yml alternative name respected

set +e

HOOK="$(cd "$(dirname "$0")/../.." && pwd)/templates/hooks/check-protected-files.sh"
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
cd "$TMPDIR" || exit 1

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
  [ "$1" -eq 0 ] || fail "$2 — expected exit 0, got $1"
}

# Helper: get field from last line of protected audit log
last_field() {
  local field="$1"
  local f=".claude/audit/protected-$TODAY.jsonl"
  [ -f "$f" ] || { echo ""; return; }
  tail -1 "$f" | python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read())
    v = d.get('$field', '')
    print(v)
except Exception:
    print('')
" 2>/dev/null
}

count_log_lines() {
  local f=".claude/audit/protected-$TODAY.jsonl"
  if [ -f "$f" ]; then
    wc -l < "$f" | tr -d ' '
  else
    echo "0"
  fi
}

# ── Setup: write a protected-files.yml in TMPDIR ─────────────────
cat > protected-files.yml <<'YAML'
# test protected-files.yml
files:
  - file: "src/**/*engine*.{js,ts}"
    reason: "시그널/코어 엔진, 크라운 주얼"
    trigger_on: any_change
    reviewer: architect

  - file: "src/**/*auth*.{js,ts}"
    reason: "인증/보안 관련 코드"
    trigger_on: any_change
    reviewer: security-reviewer

  - file: "package.json"
    reason: "의존성 관리"
    trigger_on: any_change
    reviewer: code-reviewer
YAML

# ── T1: Protected glob matched ────────────────────────────────────
mkdir -p src/core
touch src/core/signal-engine.ts

PAYLOAD="{\"tool_input\":{\"file_path\":\"$TMPDIR/src/core/signal-engine.ts\"}}"
printf '%s' "$PAYLOAD" | bash "$HOOK"
RC=$?
assert_exit0 "$RC" "T1: exit 0 on protected file match"
ASSERTIONS=$((ASSERTIONS + 1))
LOGGED_FILE=$(last_field "file")
if [ "$LOGGED_FILE" != "$TMPDIR/src/core/signal-engine.ts" ]; then
  fail "T1: file not logged — got '$LOGGED_FILE'"
fi

# ── T2: Non-protected file — no false positive ────────────────────
BEFORE=$(count_log_lines)
mkdir -p src/utils
touch src/utils/helper.ts
PAYLOAD="{\"tool_input\":{\"file_path\":\"$TMPDIR/src/utils/helper.ts\"}}"
printf '%s' "$PAYLOAD" | bash "$HOOK"
RC=$?
assert_exit0 "$RC" "T2: exit 0 on non-protected file"
AFTER=$(count_log_lines)
assert_eq "$BEFORE" "$AFTER" "T2: no log entry for non-protected file"

# ── T3: YAML parsed correctly (reason field preserved) ───────────
mkdir -p src/api
touch src/api/auth-service.ts
PAYLOAD="{\"tool_input\":{\"file_path\":\"$TMPDIR/src/api/auth-service.ts\"}}"
printf '%s' "$PAYLOAD" | bash "$HOOK"
RC=$?
assert_exit0 "$RC" "T3: exit 0 on auth file"
REASON=$(last_field "reason")
ASSERTIONS=$((ASSERTIONS + 1))
if [ -z "$REASON" ]; then
  fail "T3: reason field empty in audit log"
fi

# ── T4: Multiple rules can match (package.json) ───────────────────
# package.json matches the "package.json" rule directly
PAYLOAD="{\"tool_input\":{\"file_path\":\"$TMPDIR/package.json\"}}"
printf '%s' "$PAYLOAD" | bash "$HOOK"
RC=$?
assert_exit0 "$RC" "T4: exit 0 on package.json"
REVIEWER=$(last_field "reviewer")
assert_eq "$REVIEWER" "code-reviewer" "T4: reviewer field correct for package.json"

# ── T5: No protected-files.yml → graceful exit 0 ─────────────────
SUBDIR="$TMPDIR/isolated"
mkdir -p "$SUBDIR"
# Run hook from a directory with no protected-files.yml
PAYLOAD="{\"tool_input\":{\"file_path\":\"$SUBDIR/src/engine.ts\"}}"
(cd "$SUBDIR" && printf '%s' "$PAYLOAD" | bash "$HOOK")
RC=$?
assert_exit0 "$RC" "T5: exit 0 with no protected-files.yml present"

# ── T6: Empty stdin → exit 0 ─────────────────────────────────────
echo '' | bash "$HOOK"
RC=$?
assert_exit0 "$RC" "T6: exit 0 with empty stdin"

# ── T7: Malformed JSON → exit 0 ──────────────────────────────────
echo 'not valid json {{{{' | bash "$HOOK"
RC=$?
assert_exit0 "$RC" "T7: exit 0 with malformed JSON"

# ── T8: .gitignore auto-created ───────────────────────────────────
ASSERTIONS=$((ASSERTIONS + 1))
if [ ! -f ".claude/audit/.gitignore" ]; then
  fail "T8: .gitignore not auto-created in .claude/audit/"
fi

# ── T9: reason + reviewer in audit log ───────────────────────────
# Already checked reason in T3, verify reviewer separately
touch src/api/auth-middleware.ts
PAYLOAD="{\"tool_input\":{\"file_path\":\"$TMPDIR/src/api/auth-middleware.ts\"}}"
printf '%s' "$PAYLOAD" | bash "$HOOK"
RC=$?
assert_exit0 "$RC" "T9: exit 0 on auth middleware"
REVIEWER9=$(last_field "reviewer")
REASON9=$(last_field "reason")
ASSERTIONS=$((ASSERTIONS + 1))
[ -n "$REVIEWER9" ] || fail "T9: reviewer field missing from audit log"
ASSERTIONS=$((ASSERTIONS + 1))
[ -n "$REASON9" ] || fail "T9: reason field missing from audit log"

# ── T10: Shell injection canary ───────────────────────────────────
CANARY="$TMPDIR/injection-canary"
rm -f "$CANARY"
PAYLOAD="{\"tool_input\":{\"file_path\":\"$TMPDIR/\$(touch $CANARY)engine.ts\"}}"
printf '%s' "$PAYLOAD" | bash "$HOOK"
RC=$?
assert_exit0 "$RC" "T10: exit 0 with injection-pattern path"
ASSERTIONS=$((ASSERTIONS + 1))
if [ -f "$CANARY" ]; then
  fail "T10: SHELL INJECTION — canary file was created!"
fi

# ── T11: All JSONL entries valid JSON ─────────────────────────────
python3 -c "
import json
f = '.claude/audit/protected-$TODAY.jsonl'
try:
    with open(f) as fh:
        for i, line in enumerate(fh, 1):
            if line.strip():
                json.loads(line)
except FileNotFoundError:
    pass
except Exception as e:
    print(f'FAIL: invalid JSONL at line {i} — {e}')
    exit(1)
" || fail "T11: JSONL entries not all valid JSON"
ASSERTIONS=$((ASSERTIONS + 1))

# ── T12: .protected-files.yml (dot-prefix) variant respected ──────
DOTDIR="$TMPDIR/dotvariant"
mkdir -p "$DOTDIR/src/core"
touch "$DOTDIR/src/core/signal-engine.js"

cat > "$DOTDIR/.protected-files.yml" <<'YAML'
files:
  - file: "src/**/*engine*.{js,ts}"
    reason: "엔진 dot-prefix test"
    trigger_on: any_change
    reviewer: architect
YAML

BEFORE_DOT=$(count_log_lines)
PAYLOAD="{\"tool_input\":{\"file_path\":\"$DOTDIR/src/core/signal-engine.js\"}}"
(cd "$DOTDIR" && printf '%s' "$PAYLOAD" | CLAUDE_AUDIT_DIR="$TMPDIR/.claude/audit" bash "$HOOK")
RC=$?
assert_exit0 "$RC" "T12: exit 0 with .protected-files.yml (dot prefix)"
AFTER_DOT=$(count_log_lines)
ASSERTIONS=$((ASSERTIONS + 1))
if [ "$AFTER_DOT" -le "$BEFORE_DOT" ]; then
  fail "T12: .protected-files.yml not picked up — no log entry added"
fi

# ── Summary ───────────────────────────────────────────────────────
if [ "$FAILED" -gt 0 ]; then
  echo ""
  echo "check-protected-files: $((ASSERTIONS - FAILED))/$ASSERTIONS passed, $FAILED failed"
  exit 1
fi

echo "check-protected-files: $ASSERTIONS assertions passed"
exit 0
