#!/usr/bin/env bash
# Tests for templates/hooks/check-config-protection.sh (v8 item 7.3)
#
# Verifies:
#   1. Exits 0 on every input variant
#   2. Detects weakening patterns in config files (tsconfig, eslintrc, etc.)
#   3. Ignores non-config files (no log entry)
#   4. Ignores properly strict configs (no false positive)
#   5. Handles missing file_path, malformed JSON, empty stdin
#   6. Shell injection guard (TMPDIR canary)
#   7. .gitignore auto-created
#   8. All JSONL entries valid JSON

set +e

HOOK="$(cd "$(dirname "$0")/../.." && pwd)/templates/hooks/check-config-protection.sh"
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

# Capture date once to avoid midnight race
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

# Helper: get last log entry's named field
last_field() {
  local field="$1"
  local f=".claude/audit/config-guard-$TODAY.jsonl"
  [ -f "$f" ] || { echo ""; return; }
  tail -1 "$f" | python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read())
    v = d.get('$field', '')
    if isinstance(v, list):
        print(','.join(v))
    else:
        print(v)
except Exception:
    print('')
" 2>/dev/null
}

# Helper: count log lines
count_log_lines() {
  local f=".claude/audit/config-guard-$TODAY.jsonl"
  if [ -f "$f" ]; then
    wc -l < "$f" | tr -d ' '
  else
    echo "0"
  fi
}

# Helper: check if list-valued field contains a specific element
last_has_pattern() {
  local pat="$1"
  local patterns
  patterns=$(last_field weakening_patterns)
  case "$patterns" in
    *$pat*) return 0 ;;
    *) return 1 ;;
  esac
}

# ── Test 1: tsconfig.json with strict:false → detected ──────────
mkdir -p proj1
cat > proj1/tsconfig.json <<'EOF'
{
  "compilerOptions": {
    "strict": false,
    "target": "es2020"
  }
}
EOF
PAYLOAD="{\"tool_input\":{\"file_path\":\"$TMPDIR/proj1/tsconfig.json\"}}"
printf '%s' "$PAYLOAD" | bash "$HOOK"
RC=$?
assert_eq "$RC" "0" "T1: exit 0 with weakened tsconfig"
ASSERTIONS=$((ASSERTIONS + 1))
if ! last_has_pattern "strict_false"; then
  fail "T1: strict_false not detected (patterns='$(last_field weakening_patterns)')"
fi
assert_eq "$(last_field file)" "$TMPDIR/proj1/tsconfig.json" "T1: file path recorded"

# ── Test 2: non-config file → no log ─────────────────────────────
BEFORE=$(count_log_lines)
mkdir -p proj2/src
cat > proj2/src/foo.ts <<'EOF'
const x: any = "whatever";
// @ts-ignore
export const y = 42;
EOF
PAYLOAD="{\"tool_input\":{\"file_path\":\"$TMPDIR/proj2/src/foo.ts\"}}"
printf '%s' "$PAYLOAD" | bash "$HOOK"
RC=$?
assert_eq "$RC" "0" "T2: exit 0 with non-config file"
AFTER=$(count_log_lines)
assert_eq "$BEFORE" "$AFTER" "T2: no log entry for non-config file (even with @ts-ignore)"

# ── Test 3: tsconfig with strict:true → no log ───────────────────
BEFORE=$(count_log_lines)
mkdir -p proj3
cat > proj3/tsconfig.json <<'EOF'
{
  "compilerOptions": {
    "strict": true,
    "target": "es2020"
  }
}
EOF
PAYLOAD="{\"tool_input\":{\"file_path\":\"$TMPDIR/proj3/tsconfig.json\"}}"
printf '%s' "$PAYLOAD" | bash "$HOOK"
RC=$?
assert_eq "$RC" "0" "T3: exit 0 with strict tsconfig"
AFTER=$(count_log_lines)
assert_eq "$BEFORE" "$AFTER" "T3: no log entry for properly strict config"

# ── Test 4: eslintrc with rule "off" → detected ─────────────────
mkdir -p proj4
cat > proj4/.eslintrc.json <<'EOF'
{
  "rules": {
    "no-unused-vars": "off",
    "no-console": "error"
  }
}
EOF
PAYLOAD="{\"tool_input\":{\"file_path\":\"$TMPDIR/proj4/.eslintrc.json\"}}"
printf '%s' "$PAYLOAD" | bash "$HOOK"
RC=$?
assert_eq "$RC" "0" "T4: exit 0 with eslint off rule"
ASSERTIONS=$((ASSERTIONS + 1))
if ! last_has_pattern "eslint_rule_off"; then
  fail "T4: eslint_rule_off not detected (patterns='$(last_field weakening_patterns)')"
fi

# ── Test 5: multiple weakening patterns in one file ─────────────
mkdir -p proj5
cat > proj5/tsconfig.json <<'EOF'
{
  "compilerOptions": {
    "strict": false,
    "noImplicitAny": false,
    "skipLibCheck": true,
    "allowJs": true
  }
}
EOF
PAYLOAD="{\"tool_input\":{\"file_path\":\"$TMPDIR/proj5/tsconfig.json\"}}"
printf '%s' "$PAYLOAD" | bash "$HOOK"
RC=$?
assert_eq "$RC" "0" "T5: exit 0 with multiple weakening"
for p in strict_false noImplicitAny_false skipLibCheck_true allowJs_true; do
  ASSERTIONS=$((ASSERTIONS + 1))
  if ! last_has_pattern "$p"; then
    fail "T5: expected '$p' in patterns, got '$(last_field weakening_patterns)'"
  fi
done

# ── Test 6: @ts-ignore in a tsconfig-adjacent file (comment) ────
# tsconfig.json with a @ts-ignore comment (valid JSON with // comment would
# normally fail parsing, but we use a vitest.config.ts which allows it).
mkdir -p proj6
cat > proj6/vitest.config.ts <<'EOF'
import { defineConfig } from 'vitest/config'
// @ts-ignore
export default defineConfig({ test: { globals: true } })
EOF
PAYLOAD="{\"tool_input\":{\"file_path\":\"$TMPDIR/proj6/vitest.config.ts\"}}"
printf '%s' "$PAYLOAD" | bash "$HOOK"
RC=$?
assert_eq "$RC" "0" "T6: exit 0 with @ts-ignore in vitest.config.ts"
ASSERTIONS=$((ASSERTIONS + 1))
if ! last_has_pattern "ts_ignore_comment"; then
  fail "T6: ts_ignore_comment not detected (patterns='$(last_field weakening_patterns)')"
fi

# ── Test 7: empty stdin → exit 0 ─────────────────────────────────
echo '' | bash "$HOOK"
RC=$?
assert_eq "$RC" "0" "T7: exit 0 with empty stdin"

# ── Test 8: malformed JSON → exit 0 ──────────────────────────────
echo 'not json' | bash "$HOOK"
RC=$?
assert_eq "$RC" "0" "T8: exit 0 with malformed JSON"

# ── Test 9: missing tool_input → exit 0 ──────────────────────────
printf '%s' '{}' | bash "$HOOK"
RC=$?
assert_eq "$RC" "0" "T9: exit 0 with empty payload"

# ── Test 10: missing file_path → exit 0 ─────────────────────────
printf '%s' '{"tool_input":{}}' | bash "$HOOK"
RC=$?
assert_eq "$RC" "0" "T10: exit 0 with missing file_path"

# ── Test 11: non-existent file → exit 0 (silent, no log) ────────
BEFORE=$(count_log_lines)
printf '%s' '{"tool_input":{"file_path":"/nonexistent/tsconfig.json"}}' | bash "$HOOK"
RC=$?
assert_eq "$RC" "0" "T11: exit 0 with non-existent config file"
AFTER=$(count_log_lines)
assert_eq "$BEFORE" "$AFTER" "T11: no log entry for non-existent file"

# ── Test 12: shell injection guard ──────────────────────────────
CANARY="$TMPDIR/injection-canary"
rm -f "$CANARY"
PAYLOAD="{\"tool_input\":{\"file_path\":\"$TMPDIR/\$(touch $CANARY).json\"}}"
printf '%s' "$PAYLOAD" | bash "$HOOK"
RC=$?
assert_eq "$RC" "0" "T12: exit 0 with injection-pattern path"
if [ -f "$CANARY" ]; then
  fail "T12: SHELL INJECTION — canary file was created!"
fi

# ── Test 13: .gitignore auto-created ─────────────────────────────
if [ ! -f .claude/audit/.gitignore ]; then
  fail "T13: .gitignore not auto-created in .claude/audit/"
fi

# ── Test 14: all JSONL entries valid JSON ────────────────────────
python3 -c "
import json
f = '.claude/audit/config-guard-$TODAY.jsonl'
try:
    with open(f) as fh:
        for line in fh:
            if line.strip():
                json.loads(line)
except FileNotFoundError:
    pass  # No log file means no bad entries — that's fine
except Exception as e:
    print(f'FAIL: invalid JSONL — {e}')
    exit(1)
" || fail "T14: not all JSONL entries valid JSON"

# ── Summary ───────────────────────────────────────────────────────
if [ "$FAILED" -gt 0 ]; then
  echo ""
  echo "check-config-protection: $((ASSERTIONS - FAILED))/$ASSERTIONS passed, $FAILED failed"
  exit 1
fi

echo "check-config-protection: $ASSERTIONS assertions passed"
exit 0
