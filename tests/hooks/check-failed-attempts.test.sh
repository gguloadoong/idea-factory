#!/usr/bin/env bash
# Tests for templates/hooks/check-failed-attempts.sh (v8 item 4.3)
#
# Verifies:
#   1. 파일 없을 때 조용히 exit 0
#   2. 빈 파일일 때 조용히 exit 0
#   3. 주석만 있는 파일은 무시하고 exit 0
#   4. 엔트리 있을 때 경고 헤더 출력
#   5. what 필드 출력 확인
#   6. reason 필드 출력 확인
#   7. 최근 10개만 표시 (11개 이상일 때 첫 엔트리 제외)
#   8. malformed JSONL 에도 exit 0
#   9. 빈 stdin 에도 exit 0
#  10. exit 코드가 항상 0

set +e  # assertions track failures manually

HOOK="$(cd "$(dirname "$0")/../.." && pwd)/templates/hooks/check-failed-attempts.sh"
if [ ! -f "$HOOK" ]; then
  echo "  FAIL: hook not found at $HOOK"
  exit 1
fi
chmod +x "$HOOK"

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
    *) fail "$3 — expected output to contain '$2', got '$1'" ;;
  esac
}

assert_empty() {
  [ -z "$1" ] || fail "$2 — expected empty output, got '$1'"
}

assert_not_contains() {
  case "$1" in
    *"$2"*) fail "$3 — expected output NOT to contain '$2'" ;;
    *) ;;
  esac
}

# Helper: write a valid JSONL entry
make_entry() {
  local what="$1" reason="$2" lesson="${3:-교훈없음}"
  python3 -c "
import json, sys
print(json.dumps({'ts':'2026-04-13T10:00:00Z','what':sys.argv[1],'reason':sys.argv[2],'lesson':sys.argv[3]}, ensure_ascii=False))
" "$what" "$reason" "$lesson"
}

# ── Test 1: 파일 없을 때 exit 0, 출력 없음 ───────────────────────────
LEDGER="$TMPDIR/nonexistent/failed-attempts.jsonl"
OUT=$(FAILED_ATTEMPTS_FILE="$LEDGER" bash "$HOOK" 2>/dev/null)
RC=$?
assert_eq "$RC" "0" "T1: exit 0 when file missing"
assert_empty "$OUT" "T1: no output when file missing"

# ── Test 2: 빈 파일 → exit 0, 출력 없음 ─────────────────────────────
LEDGER2="$TMPDIR/empty-ledger.jsonl"
touch "$LEDGER2"
OUT=$(FAILED_ATTEMPTS_FILE="$LEDGER2" bash "$HOOK" 2>/dev/null)
RC=$?
assert_eq "$RC" "0" "T2: exit 0 for empty file"
assert_empty "$OUT" "T2: no output for empty file"

# ── Test 3: 주석만 있는 파일 → exit 0, 출력 없음 ─────────────────────
LEDGER3="$TMPDIR/comments-only.jsonl"
cat > "$LEDGER3" <<'EOF'
# failed-attempts.jsonl — 실패한 시도 기록 (append-only)
# 형식: {"ts":"...", "what":"...", "reason":"...", "lesson":"..."}

EOF
OUT=$(FAILED_ATTEMPTS_FILE="$LEDGER3" bash "$HOOK" 2>/dev/null)
RC=$?
assert_eq "$RC" "0" "T3: exit 0 for comments-only file"
assert_empty "$OUT" "T3: no output for comments-only file"

# ── Test 4: 엔트리 있을 때 경고 헤더 출력 ────────────────────────────
LEDGER4="$TMPDIR/with-entries.jsonl"
make_entry "MOMENTUM_ENTRY_PCT 2.5 설정" "과도한 손실 발생" "1.0 이하 유지" > "$LEDGER4"
OUT=$(FAILED_ATTEMPTS_FILE="$LEDGER4" bash "$HOOK" 2>/dev/null)
RC=$?
assert_eq "$RC" "0" "T4: exit 0 with entries"
assert_contains "$OUT" "이전 세션에서 실패한 시도가 기록되어 있습니다" "T4: warning header present"

# ── Test 5: what 필드 출력 확인 ──────────────────────────────────────
assert_contains "$OUT" "MOMENTUM_ENTRY_PCT 2.5 설정" "T5: what field in output"

# ── Test 6: reason 필드 출력 확인 ────────────────────────────────────
assert_contains "$OUT" "과도한 손실 발생" "T6: reason field in output"

# ── Test 7: 최근 10개만 표시 (11개 중 첫 번째 제외) ──────────────────
LEDGER7="$TMPDIR/many-entries.jsonl"
# Write 11 entries; first one has unique marker "ENTRY_ZERO"
make_entry "ENTRY_ZERO 시도" "첫 번째 실패" "버려야 함" > "$LEDGER7"
for i in $(seq 1 10); do
  make_entry "시도번호_${i}" "실패사유_${i}" "교훈_${i}" >> "$LEDGER7"
done
OUT=$(FAILED_ATTEMPTS_FILE="$LEDGER7" bash "$HOOK" 2>/dev/null)
RC=$?
assert_eq "$RC" "0" "T7: exit 0 with 11 entries"
assert_not_contains "$OUT" "ENTRY_ZERO" "T7: oldest entry excluded when >10 entries"
assert_contains "$OUT" "시도번호_10" "T7: most recent entry included"

# ── Test 8: malformed JSONL에도 exit 0 ───────────────────────────────
LEDGER8="$TMPDIR/malformed.jsonl"
printf 'not valid json\n{also bad\n' > "$LEDGER8"
FAILED_ATTEMPTS_FILE="$LEDGER8" bash "$HOOK" 2>/dev/null
RC=$?
assert_eq "$RC" "0" "T8: exit 0 for malformed JSONL"

# ── Test 9: 빈 stdin에도 exit 0 ──────────────────────────────────────
LEDGER9="$TMPDIR/empty2.jsonl"
touch "$LEDGER9"
echo '' | FAILED_ATTEMPTS_FILE="$LEDGER9" bash "$HOOK" 2>/dev/null
RC=$?
assert_eq "$RC" "0" "T9: exit 0 with empty stdin"

# ── Test 10: 유효 엔트리 + malformed 혼재 → exit 0, 유효 항목만 출력 ─
LEDGER10="$TMPDIR/mixed.jsonl"
printf 'bad line\n' > "$LEDGER10"
make_entry "유효한 시도" "유효한 실패사유" "유효한 교훈" >> "$LEDGER10"
printf 'another bad line\n' >> "$LEDGER10"
OUT=$(FAILED_ATTEMPTS_FILE="$LEDGER10" bash "$HOOK" 2>/dev/null)
RC=$?
assert_eq "$RC" "0" "T10: exit 0 with mixed valid/invalid lines"
assert_contains "$OUT" "유효한 시도" "T10: valid entry shown despite malformed lines"

# ── Summary ───────────────────────────────────────────────────────────
if [ "$FAILED" -gt 0 ]; then
  echo ""
  echo "check-failed-attempts: $FAILED assertion(s) failed"
  exit 1
fi

echo "check-failed-attempts: 10 assertions passed"
exit 0
