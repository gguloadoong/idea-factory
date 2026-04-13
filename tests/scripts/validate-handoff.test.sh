#!/usr/bin/env bash
# tests/scripts/validate-handoff.test.sh — unit tests for scripts/validate-handoff.sh
#
# Run: bash tests/scripts/validate-handoff.test.sh
# Or via: bash tests/run-all.sh

set +e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/scripts/validate-handoff.sh"
TMPDIR_TEST="$(mktemp -d)"

PASS=0
FAIL=0

# --- Helpers ---

assert_exit() {
  local label="$1"
  local expected="$2"
  local actual="$3"
  if [ "$actual" -eq "$expected" ]; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label (expected exit $expected, got $actual)"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local label="$1"
  local pattern="$2"
  local output="$3"
  if echo "$output" | grep -qE "$pattern"; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label (pattern '$pattern' not found)"
    echo "    output: $(echo "$output" | head -8)"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local label="$1"
  local pattern="$2"
  local output="$3"
  if ! echo "$output" | grep -qE "$pattern"; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label (pattern '$pattern' unexpectedly found)"
    echo "    output: $(echo "$output" | head -8)"
    FAIL=$((FAIL + 1))
  fi
}

# Cleanup on exit
cleanup() { rm -rf "$TMPDIR_TEST"; }
trap cleanup EXIT

echo "validate-handoff.sh tests"
echo "========================="

# -----------------------------------------------------------------------
# T1: exit 0 always — normal invocation with matching files
# -----------------------------------------------------------------------
echo ""
echo "T1: exit 0 with valid handoff + invariants"

INVARIANTS="$TMPDIR_TEST/invariants.md"
HANDOFF="$TMPDIR_TEST/handoff.md"

cat > "$INVARIANTS" << 'EOF'
## 보안 규칙
- exit 0 보장 (advisory only)
- `시크릿` 하드코딩 금지
- 환경변수 사용 필수
- shell injection 방지
EOF

cat > "$HANDOFF" << 'EOF'
# Session Handoff

## 현재 Phase
v8 구현

## 핵심 불변 조건
- exit 0 보장
- 시크릿 하드코딩 금지
- 환경변수 사용
- shell injection 방지

## 다음 작업
validate-handoff 구현 완료
EOF

output=$(bash "$SCRIPT" --handoff "$HANDOFF" --invariants "$INVARIANTS" 2>&1)
rc=$?
assert_exit "T1 exit code is 0" 0 "$rc"

# -----------------------------------------------------------------------
# T2: high coverage → 통과 메시지 출력
# -----------------------------------------------------------------------
echo ""
echo "T2: high coverage → pass message"

output=$(bash "$SCRIPT" --handoff "$HANDOFF" --invariants "$INVARIANTS" 2>&1)
assert_contains "T2 coverage OK message" "커버리지 OK|OK" "$output"

# -----------------------------------------------------------------------
# T3: low coverage → 경고 메시지 출력
# -----------------------------------------------------------------------
echo ""
echo "T3: low coverage → warning message"

HANDOFF_SPARSE="$TMPDIR_TEST/handoff-sparse.md"
cat > "$HANDOFF_SPARSE" << 'EOF'
# Minimal handoff

nothing useful here
EOF

output=$(bash "$SCRIPT" --handoff "$HANDOFF_SPARSE" --invariants "$INVARIANTS" 2>&1)
rc=$?
assert_exit "T3 exit code is 0" 0 "$rc"
assert_contains "T3 low coverage warning" "커버리지 미달|미달|WARN" "$output"

# -----------------------------------------------------------------------
# T4: --verbose 모드에서 누락 목록 출력
# -----------------------------------------------------------------------
echo ""
echo "T4: --verbose shows missing keywords"

output=$(bash "$SCRIPT" --handoff "$HANDOFF_SPARSE" --invariants "$INVARIANTS" --verbose 2>&1)
rc=$?
assert_exit "T4 exit code is 0" 0 "$rc"
assert_contains "T4 missing list header" "누락|missing" "$output"

# -----------------------------------------------------------------------
# T5: handoff 파일 없을 때 graceful exit 0
# -----------------------------------------------------------------------
echo ""
echo "T5: missing handoff file → graceful exit 0"

output=$(bash "$SCRIPT" --handoff "$TMPDIR_TEST/nonexistent-handoff.md" --invariants "$INVARIANTS" 2>&1)
rc=$?
assert_exit "T5 exit code is 0" 0 "$rc"
assert_contains "T5 graceful message" "not found|없|graceful" "$output"

# -----------------------------------------------------------------------
# T6: invariants 파일 없을 때 graceful exit 0
# -----------------------------------------------------------------------
echo ""
echo "T6: missing invariants file → graceful exit 0"

output=$(bash "$SCRIPT" --handoff "$HANDOFF" --invariants "$TMPDIR_TEST/nonexistent-invariants.md" 2>&1)
rc=$?
assert_exit "T6 exit code is 0" 0 "$rc"
assert_contains "T6 graceful message" "not found|없|graceful" "$output"

# -----------------------------------------------------------------------
# T7: 빈 파일들에 graceful 처리
# -----------------------------------------------------------------------
echo ""
echo "T7: empty files → graceful exit 0"

EMPTY_HANDOFF="$TMPDIR_TEST/empty-handoff.md"
EMPTY_INVARIANTS="$TMPDIR_TEST/empty-invariants.md"
touch "$EMPTY_HANDOFF" "$EMPTY_INVARIANTS"

output=$(bash "$SCRIPT" --handoff "$EMPTY_HANDOFF" --invariants "$EMPTY_INVARIANTS" 2>&1)
rc=$?
assert_exit "T7 exit code is 0" 0 "$rc"
assert_contains "T7 empty graceful message" "empty|비어|graceful|없" "$output"

# -----------------------------------------------------------------------
# T8: exit 0 보장 — 잘못된 인자에도 exit 0
# -----------------------------------------------------------------------
echo ""
echo "T8: unknown args → still exits 0"

output=$(bash "$SCRIPT" --handoff "$HANDOFF" --invariants "$INVARIANTS" --unknown-arg foo 2>&1)
rc=$?
assert_exit "T8 exit code is 0" 0 "$rc"

# -----------------------------------------------------------------------
# T9: 커버리지 점수가 출력에 포함됨
# -----------------------------------------------------------------------
echo ""
echo "T9: coverage score is printed"

output=$(bash "$SCRIPT" --handoff "$HANDOFF" --invariants "$INVARIANTS" 2>&1)
rc=$?
assert_exit "T9 exit code is 0" 0 "$rc"
assert_contains "T9 coverage percent in output" "[0-9]+%" "$output"

# -----------------------------------------------------------------------
# T10: --threshold override works
# -----------------------------------------------------------------------
echo ""
echo "T10: --threshold 0 → always pass"

output=$(bash "$SCRIPT" --handoff "$HANDOFF_SPARSE" --invariants "$INVARIANTS" --threshold 0 2>&1)
rc=$?
assert_exit "T10 exit code is 0" 0 "$rc"
assert_contains "T10 threshold 0 pass" "커버리지 OK|OK" "$output"

# -----------------------------------------------------------------------
# T11: --threshold 100 → always warn (unless perfect coverage)
# -----------------------------------------------------------------------
echo ""
echo "T11: --threshold 100 on sparse handoff → warning"

output=$(bash "$SCRIPT" --handoff "$HANDOFF_SPARSE" --invariants "$INVARIANTS" --threshold 100 2>&1)
rc=$?
assert_exit "T11 exit code is 0" 0 "$rc"
assert_contains "T11 threshold 100 warn" "커버리지 미달|미달|WARN" "$output"

# -----------------------------------------------------------------------
# T12: invalid --threshold value → graceful (uses default)
# -----------------------------------------------------------------------
echo ""
echo "T12: invalid --threshold value → graceful exit 0"

output=$(bash "$SCRIPT" --handoff "$HANDOFF" --invariants "$INVARIANTS" --threshold abc 2>&1)
rc=$?
assert_exit "T12 exit code is 0" 0 "$rc"

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
echo ""
echo "========================="
echo "Results: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

exit 0
