#!/usr/bin/env bash
# Tests for templates/hooks/check-secret-scan.sh (v8 item 1.2)
#
# Verifies:
#   1.  AWS key pattern detected (HIGH)
#   2.  OpenAI key pattern detected (HIGH)
#   3.  GitHub token pattern detected (HIGH)
#   4.  console.log(apiKey) detected (WARN)
#   5.  fetch with token= query param detected (WARN)
#   6.  process.env.API_KEY usage (no log) — false positive guard
#   7.  Empty stdin → exit 0
#   8.  Malformed JSON → exit 0
#   9.  Non-existent file path → exit 0, no log
#   10. .gitignore auto-created
#   11. Non-code file (.md) skipped — no log
#   12. Shell injection canary — no file created
#   13. Slack token detected (HIGH)
#   14. Hardcoded password detected (HIGH)
#   15. throw new Error with process.env detected (WARN)
#   16. All JSONL entries valid JSON

set +e

HOOK="$(cd "$(dirname "$0")/../.." && pwd)/templates/hooks/check-secret-scan.sh"
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
LOG_FILE=".claude/audit/secret-scan-$TODAY.jsonl"

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

assert_true() {
  ASSERTIONS=$((ASSERTIONS + 1))
  [ "$1" = "0" ] || fail "$2"
}

# Helper: count log lines
count_log_lines() {
  if [ -f "$LOG_FILE" ]; then
    wc -l < "$LOG_FILE" | tr -d ' '
  else
    echo "0"
  fi
}

# Helper: get field from last log entry
last_field() {
  local field="$1"
  [ -f "$LOG_FILE" ] || { echo ""; return; }
  tail -1 "$LOG_FILE" | python3 -c "
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

# Helper: check last entry's patterns_found contains given id
last_has_pattern() {
  local pat="$1"
  local patterns
  patterns=$(last_field patterns_found)
  case "$patterns" in
    *"$pat"*) return 0 ;;
    *) return 1 ;;
  esac
}

# Helper: create a JS file with given content and return its path
make_js() {
  local name="$1"
  local body="$2"
  mkdir -p "$(dirname "$name")"
  printf '%s\n' "$body" > "$name"
  echo "$TMPDIR/$name"
}

# ── Test 1: AWS key detected ─────────────────────────────────────
T1_FILE=$(make_js "t1/index.js" 'const key = "AKIAIOSFODNN7EXAMPLE";')
PAYLOAD="{\"tool_input\":{\"file_path\":\"$T1_FILE\"}}"
printf '%s' "$PAYLOAD" | bash "$HOOK" 2>/dev/null
RC=$?
assert_eq "$RC" "0" "T1: exit 0 with AWS key"
ASSERTIONS=$((ASSERTIONS + 1))
if ! last_has_pattern "aws_key"; then
  fail "T1: aws_key not detected (patterns='$(last_field patterns_found)')"
fi
assert_eq "$(last_field severity)" "HIGH" "T1: severity=HIGH for AWS key"

# ── Test 2: OpenAI key detected ──────────────────────────────────
T2_FILE=$(make_js "t2/config.ts" 'const client = new OpenAI({ apiKey: "sk-abcdefghijklmnopqrstuvwxyz1234" });')
PAYLOAD="{\"tool_input\":{\"file_path\":\"$T2_FILE\"}}"
printf '%s' "$PAYLOAD" | bash "$HOOK" 2>/dev/null
RC=$?
assert_eq "$RC" "0" "T2: exit 0 with OpenAI key"
ASSERTIONS=$((ASSERTIONS + 1))
if ! last_has_pattern "openai_key"; then
  fail "T2: openai_key not detected (patterns='$(last_field patterns_found)')"
fi

# ── Test 3: GitHub token detected ────────────────────────────────
T3_FILE=$(make_js "t3/deploy.js" 'const token = "ghp_abcdefghijklmnopqrstuvwxyzABCDEFGHIJ";')
PAYLOAD="{\"tool_input\":{\"file_path\":\"$T3_FILE\"}}"
printf '%s' "$PAYLOAD" | bash "$HOOK" 2>/dev/null
RC=$?
assert_eq "$RC" "0" "T3: exit 0 with GitHub token"
ASSERTIONS=$((ASSERTIONS + 1))
if ! last_has_pattern "github_token"; then
  fail "T3: github_token not detected (patterns='$(last_field patterns_found)')"
fi

# ── Test 4: console.log(apiKey) detected ─────────────────────────
T4_FILE=$(make_js "t4/debug.js" 'console.log("api key is:", apiKey);')
PAYLOAD="{\"tool_input\":{\"file_path\":\"$T4_FILE\"}}"
printf '%s' "$PAYLOAD" | bash "$HOOK" 2>/dev/null
RC=$?
assert_eq "$RC" "0" "T4: exit 0 with console.log(apiKey)"
ASSERTIONS=$((ASSERTIONS + 1))
if ! last_has_pattern "console_log_secret"; then
  fail "T4: console_log_secret not detected (patterns='$(last_field patterns_found)')"
fi
assert_eq "$(last_field severity)" "WARN" "T4: severity=WARN for console.log"

# ── Test 5: fetch with token= detected ───────────────────────────
T5_FILE=$(make_js "t5/api.js" 'const res = await fetch(`https://api.example.com/data?token=${userToken}`);')
PAYLOAD="{\"tool_input\":{\"file_path\":\"$T5_FILE\"}}"
printf '%s' "$PAYLOAD" | bash "$HOOK" 2>/dev/null
RC=$?
assert_eq "$RC" "0" "T5: exit 0 with fetch token="
ASSERTIONS=$((ASSERTIONS + 1))
if ! last_has_pattern "fetch_token"; then
  fail "T5: fetch_token not detected (patterns='$(last_field patterns_found)')"
fi

# ── Test 6: process.env.API_KEY usage — no false positive ────────
BEFORE=$(count_log_lines)
T6_FILE=$(make_js "t6/safe.ts" 'const apiKey = process.env.API_KEY;
const client = new SomeClient({ apiKey });
export default client;')
PAYLOAD="{\"tool_input\":{\"file_path\":\"$T6_FILE\"}}"
printf '%s' "$PAYLOAD" | bash "$HOOK" 2>/dev/null
RC=$?
assert_eq "$RC" "0" "T6: exit 0 with safe process.env usage"
AFTER=$(count_log_lines)
assert_eq "$BEFORE" "$AFTER" "T6: no false positive for process.env.API_KEY pattern"

# ── Test 7: empty stdin → exit 0 ─────────────────────────────────
echo '' | bash "$HOOK" 2>/dev/null
RC=$?
assert_eq "$RC" "0" "T7: exit 0 with empty stdin"

# ── Test 8: malformed JSON → exit 0 ──────────────────────────────
echo 'not json at all' | bash "$HOOK" 2>/dev/null
RC=$?
assert_eq "$RC" "0" "T8: exit 0 with malformed JSON"

# ── Test 9: non-existent file → exit 0, no log ───────────────────
BEFORE=$(count_log_lines)
PAYLOAD='{"tool_input":{"file_path":"/nonexistent/src/app.ts"}}'
printf '%s' "$PAYLOAD" | bash "$HOOK" 2>/dev/null
RC=$?
assert_eq "$RC" "0" "T9: exit 0 with non-existent file"
AFTER=$(count_log_lines)
assert_eq "$BEFORE" "$AFTER" "T9: no log entry for non-existent file"

# ── Test 10: .gitignore auto-created ─────────────────────────────
ASSERTIONS=$((ASSERTIONS + 1))
if [ ! -f ".claude/audit/.gitignore" ]; then
  fail "T10: .gitignore not auto-created in .claude/audit/"
fi

# ── Test 11: .md file skipped — no log ───────────────────────────
BEFORE=$(count_log_lines)
mkdir -p t11
# Even with an AWS key inside, .md files must be skipped
printf '# Docs\n\nThe AWS key AKIAIOSFODNN7EXAMPLE was found in the log.\n' > "t11/README.md"
PAYLOAD="{\"tool_input\":{\"file_path\":\"$TMPDIR/t11/README.md\"}}"
printf '%s' "$PAYLOAD" | bash "$HOOK" 2>/dev/null
RC=$?
assert_eq "$RC" "0" "T11: exit 0 with .md file"
AFTER=$(count_log_lines)
assert_eq "$BEFORE" "$AFTER" "T11: .md file skipped — no log entry"

# ── Test 12: shell injection canary ──────────────────────────────
CANARY="$TMPDIR/injection-canary"
rm -f "$CANARY"
PAYLOAD="{\"tool_input\":{\"file_path\":\"$TMPDIR/\$(touch $CANARY).ts\"}}"
printf '%s' "$PAYLOAD" | bash "$HOOK" 2>/dev/null
RC=$?
assert_eq "$RC" "0" "T12: exit 0 with injection-pattern path"
ASSERTIONS=$((ASSERTIONS + 1))
if [ -f "$CANARY" ]; then
  fail "T12: SHELL INJECTION — canary file was created!"
fi

# ── Test 13: Slack token detected ────────────────────────────────
T13_FILE=$(make_js "t13/slack.js" 'const slack = new WebClient("xoxb-123456789012-123456789012-abc123def456");')
PAYLOAD="{\"tool_input\":{\"file_path\":\"$T13_FILE\"}}"
printf '%s' "$PAYLOAD" | bash "$HOOK" 2>/dev/null
RC=$?
assert_eq "$RC" "0" "T13: exit 0 with Slack token"
ASSERTIONS=$((ASSERTIONS + 1))
if ! last_has_pattern "slack_token"; then
  fail "T13: slack_token not detected (patterns='$(last_field patterns_found)')"
fi

# ── Test 14: Hardcoded password detected ─────────────────────────
T14_FILE=$(make_js "t14/db.py" 'conn = psycopg2.connect(password="s3cr3tP@ssw0rd")')
PAYLOAD="{\"tool_input\":{\"file_path\":\"$T14_FILE\"}}"
printf '%s' "$PAYLOAD" | bash "$HOOK" 2>/dev/null
RC=$?
assert_eq "$RC" "0" "T14: exit 0 with hardcoded password"
ASSERTIONS=$((ASSERTIONS + 1))
if ! last_has_pattern "hardcoded_password"; then
  fail "T14: hardcoded_password not detected (patterns='$(last_field patterns_found)')"
fi

# ── Test 15: throw new Error with process.env ────────────────────
T15_FILE=$(make_js "t15/validate.ts" 'if (!ok) throw new Error(`Bad token: ${process.env.SECRET_TOKEN}`);')
PAYLOAD="{\"tool_input\":{\"file_path\":\"$T15_FILE\"}}"
printf '%s' "$PAYLOAD" | bash "$HOOK" 2>/dev/null
RC=$?
assert_eq "$RC" "0" "T15: exit 0 with throw new Error(process.env)"
ASSERTIONS=$((ASSERTIONS + 1))
if ! last_has_pattern "throw_env"; then
  fail "T15: throw_env not detected (patterns='$(last_field patterns_found)')"
fi

# ── Test 16: all JSONL entries are valid JSON ─────────────────────
ASSERTIONS=$((ASSERTIONS + 1))
python3 -c "
import json
f = '$LOG_FILE'
try:
    with open(f) as fh:
        for lineno, line in enumerate(fh, 1):
            if line.strip():
                json.loads(line)
except FileNotFoundError:
    pass  # No log file is fine
except Exception as e:
    print(f'invalid JSONL at line {lineno}: {e}')
    exit(1)
" 2>/dev/null || fail "T16: not all JSONL entries are valid JSON"

# ── Summary ───────────────────────────────────────────────────────
if [ "$FAILED" -gt 0 ]; then
  echo ""
  echo "check-secret-scan: $((ASSERTIONS - FAILED))/$ASSERTIONS passed, $FAILED failed"
  exit 1
fi

echo "check-secret-scan: $ASSERTIONS assertions passed"
exit 0
