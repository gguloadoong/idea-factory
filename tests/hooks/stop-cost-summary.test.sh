#!/usr/bin/env bash
# Tests for templates/hooks/stop-cost-summary.sh (v8 item 7.2)
#
# Verifies:
#   1. Exits 0 on every input variant (v7 regression guard alignment)
#   2. Correctly sums input/output/cache tokens from a fixture transcript
#   3. Handles empty stdin, missing transcript_path, non-existent file,
#      and malformed JSONL — all exit 0 with zeros logged
#   4. Auto-creates .claude/audit/.gitignore (secret protection pattern)
#   5. JSONL output is valid JSON

set +e  # assertions track failures manually

HOOK="$(cd "$(dirname "$0")/../.." && pwd)/templates/hooks/stop-cost-summary.sh"
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

fail() {
  echo "  FAIL: $1"
  FAILED=$((FAILED + 1))
}

assert_eq() {
  [ "$1" = "$2" ] || fail "$3 — expected '$2', got '$1'"
}

# Get the last entry's named field via python3 (defensive)
last_field() {
  local field="$1"
  local f=".claude/audit/cost-$TODAY.jsonl"
  [ -f "$f" ] || { echo ""; return; }
  tail -1 "$f" | python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read())
    print(d.get('$field', ''))
except Exception:
    print('')
" 2>/dev/null
}

# ── Test 1: valid transcript with known token sums ───────────────
# Fixture: 2 assistant messages with usage. Totals:
#   input=100+200=300, output=50+50=100, cache_c=20+30=50, cache_r=10+10=20
cat > "$TMPDIR/transcript.jsonl" <<'EOF'
{"type":"assistant","message":{"usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":20,"cache_read_input_tokens":10}}}
{"type":"user","message":{"content":[{"type":"text","text":"hi"}]}}
{"type":"assistant","message":{"usage":{"input_tokens":200,"output_tokens":50,"cache_creation_input_tokens":30,"cache_read_input_tokens":10}}}
EOF

PAYLOAD="{\"session_id\":\"test-session-123\",\"transcript_path\":\"$TMPDIR/transcript.jsonl\"}"
printf '%s' "$PAYLOAD" | bash "$HOOK"
RC=$?
assert_eq "$RC" "0" "T1: exit 0 with valid transcript"
assert_eq "$(last_field input_tokens)"                "300" "T1: input_tokens summed correctly"
assert_eq "$(last_field output_tokens)"               "100" "T1: output_tokens summed correctly"
assert_eq "$(last_field cache_creation_input_tokens)" "50"  "T1: cache_creation summed correctly"
assert_eq "$(last_field cache_read_input_tokens)"     "20"  "T1: cache_read summed correctly"
assert_eq "$(last_field session)"                     "test-session-123" "T1: session_id captured"

# ── Test 2: empty stdin ──────────────────────────────────────────
echo '' | bash "$HOOK"
RC=$?
assert_eq "$RC" "0" "T2: exit 0 with empty stdin"

# ── Test 3: missing transcript_path ──────────────────────────────
printf '%s' '{"session_id":"abc"}' | bash "$HOOK"
RC=$?
assert_eq "$RC" "0" "T3: exit 0 with missing transcript_path"
# Should log zeros for token counts
assert_eq "$(last_field input_tokens)"  "0" "T3: input_tokens=0 when no transcript"
assert_eq "$(last_field output_tokens)" "0" "T3: output_tokens=0 when no transcript"

# ── Test 4: non-existent transcript file ─────────────────────────
PAYLOAD='{"session_id":"x","transcript_path":"/nonexistent/path/transcript.jsonl"}'
printf '%s' "$PAYLOAD" | bash "$HOOK"
RC=$?
assert_eq "$RC" "0" "T4: exit 0 with non-existent transcript file"
assert_eq "$(last_field input_tokens)" "0" "T4: input_tokens=0 when file missing"

# ── Test 5: malformed JSON payload ───────────────────────────────
echo 'not json at all' | bash "$HOOK"
RC=$?
assert_eq "$RC" "0" "T5: exit 0 with malformed JSON payload"

# ── Test 6: malformed transcript JSONL (some lines invalid) ──────
# Hook should skip bad lines and sum what it can.
cat > "$TMPDIR/bad-transcript.jsonl" <<'EOF'
{"type":"assistant","message":{"usage":{"input_tokens":50,"output_tokens":25,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
this is not valid JSON
{"missing":"usage"}
{"type":"assistant","message":{"usage":{"input_tokens":50,"output_tokens":25,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
EOF
PAYLOAD="{\"session_id\":\"y\",\"transcript_path\":\"$TMPDIR/bad-transcript.jsonl\"}"
printf '%s' "$PAYLOAD" | bash "$HOOK"
RC=$?
assert_eq "$RC" "0" "T6: exit 0 with partially malformed transcript"
assert_eq "$(last_field input_tokens)"  "100" "T6: input sums valid lines (50+50)"
assert_eq "$(last_field output_tokens)" "50"  "T6: output sums valid lines (25+25)"

# ── Test 7: empty transcript file ────────────────────────────────
> "$TMPDIR/empty-transcript.jsonl"
PAYLOAD="{\"session_id\":\"z\",\"transcript_path\":\"$TMPDIR/empty-transcript.jsonl\"}"
printf '%s' "$PAYLOAD" | bash "$HOOK"
RC=$?
assert_eq "$RC" "0" "T7: exit 0 with empty transcript file"
assert_eq "$(last_field input_tokens)" "0" "T7: zero tokens with empty transcript"

# ── Test 8: .gitignore auto-created ──────────────────────────────
if [ ! -f .claude/audit/.gitignore ]; then
  fail "T8: .gitignore not auto-created in .claude/audit/"
fi

# ── Test 9: all JSONL entries are valid JSON ─────────────────────
python3 -c "
import json
f = '.claude/audit/cost-$TODAY.jsonl'
try:
    with open(f) as fh:
        for line in fh:
            if line.strip():
                json.loads(line)
    exit(0)
except Exception as e:
    print(f'FAIL: invalid JSONL — {e}')
    exit(1)
" || fail "T9: not all JSONL entries valid JSON"

# ── Test 10: shell injection attempt in transcript_path ──────────
# Verifies that no shell metacharacter in transcript_path causes
# command execution (regression test for code-injection class).
# Hook should treat path literally; bogus path → not a file → zero tokens.
PAYLOAD='{"session_id":"inj","transcript_path":"/tmp/$(touch /tmp/idea-factory-injection-canary).jsonl"}'
printf '%s' "$PAYLOAD" | bash "$HOOK"
RC=$?
assert_eq "$RC" "0" "T10: exit 0 with injection-pattern path"
if [ -f /tmp/idea-factory-injection-canary ]; then
  fail "T10: SHELL INJECTION — canary file was created!"
  rm -f /tmp/idea-factory-injection-canary
fi

# ── Summary ───────────────────────────────────────────────────────
if [ "$FAILED" -gt 0 ]; then
  echo ""
  echo "stop-cost-summary: $FAILED assertion(s) failed"
  exit 1
fi

echo "stop-cost-summary: 14 assertions passed"
exit 0
