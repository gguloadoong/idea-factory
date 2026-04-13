#!/usr/bin/env bash
# Tests for scripts/record-failure.sh (v8 item 4.3)
#
# Verifies:
#   1. 정상 기록 — 파일 생성 및 엔트리 존재
#   2. JSONL 유효성 — 출력이 유효한 JSON
#   3. 필수 필드 포함 (ts, what, reason, lesson)
#   4. 디렉터리 자동 생성
#   5. 기존 파일에 append (덮어쓰지 않음)
#   6. 빈 인자 처리 — 인자 부족 시 exit 1

set +e

SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/scripts/record-failure.sh"
if [ ! -f "$SCRIPT" ]; then
  echo "  FAIL: script not found at $SCRIPT"
  exit 1
fi
chmod +x "$SCRIPT"

TMPDIR=$(mktemp -d 2>/dev/null || mktemp -d -t idea-factory 2>/dev/null)
if [ -z "$TMPDIR" ] || [ ! -d "$TMPDIR" ]; then
  echo "  FAIL: could not create temp directory"
  exit 1
fi
trap 'rm -rf "$TMPDIR"' EXIT

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
    *) fail "$3 — expected content to contain '$2'" ;;
  esac
}

assert_file_exists() {
  [ -f "$1" ] || fail "$2 — file not found: $1"
}

# ── Test 1: 정상 기록 ─────────────────────────────────────────────────
LEDGER1="$TMPDIR/test1/failed-attempts.jsonl"
FAILED_ATTEMPTS_FILE="$LEDGER1" bash "$SCRIPT" \
  "테스트 시도" "테스트 실패사유" "테스트 교훈" 2>/dev/null
RC=$?
assert_eq "$RC" "0" "T1: exit 0 on normal record"
assert_file_exists "$LEDGER1" "T1: ledger file created"

# ── Test 2: JSONL 유효성 ──────────────────────────────────────────────
CONTENT=$(cat "$LEDGER1" 2>/dev/null)
python3 -c "
import json, sys
line = sys.argv[1].strip()
if not line:
    print('empty')
    sys.exit(1)
try:
    obj = json.loads(line)
    print('valid')
except Exception as e:
    print(f'invalid: {e}')
    sys.exit(1)
" "$CONTENT" 2>/dev/null
VALID=$?
assert_eq "$VALID" "0" "T2: recorded entry is valid JSON"

# ── Test 3: 필수 필드 포함 ────────────────────────────────────────────
python3 -c "
import json, sys
obj = json.loads(sys.argv[1].strip())
for field in ['ts', 'what', 'reason', 'lesson']:
    if field not in obj:
        print(f'missing field: {field}')
        sys.exit(1)
print('all fields present')
" "$CONTENT" 2>/dev/null
FIELDS_OK=$?
assert_eq "$FIELDS_OK" "0" "T3: all required fields present (ts, what, reason, lesson)"

# ── Test 4: 디렉터리 자동 생성 ───────────────────────────────────────
LEDGER4="$TMPDIR/deep/nested/dir/failed-attempts.jsonl"
FAILED_ATTEMPTS_FILE="$LEDGER4" bash "$SCRIPT" \
  "nested test" "nested failure" "nested lesson" 2>/dev/null
RC=$?
assert_eq "$RC" "0" "T4: exit 0 with deep nested dir"
assert_file_exists "$LEDGER4" "T4: file created in auto-created nested directory"

# ── Test 5: 기존 파일에 append ────────────────────────────────────────
LEDGER5="$TMPDIR/append-test/failed-attempts.jsonl"
FAILED_ATTEMPTS_FILE="$LEDGER5" bash "$SCRIPT" \
  "첫 번째 시도" "첫 번째 실패" "첫 번째 교훈" 2>/dev/null
FAILED_ATTEMPTS_FILE="$LEDGER5" bash "$SCRIPT" \
  "두 번째 시도" "두 번째 실패" "두 번째 교훈" 2>/dev/null
LINE_COUNT=$(wc -l < "$LEDGER5" 2>/dev/null | tr -d ' ')
assert_eq "$LINE_COUNT" "2" "T5: two entries appended (not overwritten)"

# ── Test 6: 빈 인자 처리 — 인자 부족 시 exit 1 ───────────────────────
FAILED_ATTEMPTS_FILE="$TMPDIR/noop.jsonl" bash "$SCRIPT" 2>/dev/null
RC=$?
assert_eq "$RC" "1" "T6: exit 1 when required args missing"

# ── Summary ───────────────────────────────────────────────────────────
if [ "$FAILED" -gt 0 ]; then
  echo ""
  echo "record-failure: $FAILED assertion(s) failed"
  exit 1
fi

echo "record-failure: 6 assertions passed"
exit 0
