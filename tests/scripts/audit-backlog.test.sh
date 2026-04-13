#!/usr/bin/env bash
# tests/scripts/audit-backlog.test.sh — audit-backlog.py 테스트
#
# 검증 항목:
# 1. 스크립트 실행 성공 (exit 0)
# 2. --json 출력이 유효한 JSON
# 3. 모든 항목에 필수 필드 존재
# 4. 현재 drift 0건 (backlog 동기화 상태)
# 5. --help 동작

set +e
cd "$(dirname "$0")/../.." || exit 1

PASS=0
FAIL=0

assert() {
  local desc="$1"
  if eval "$2"; then
    echo "  ✓ $desc"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $desc"
    FAIL=$((FAIL + 1))
  fi
}

echo "audit-backlog.py tests"
echo "──────────────────────"

# 1. exit 0
python3 scripts/audit-backlog.py > /dev/null 2>&1
assert "text mode exits 0" "[ $? -eq 0 ]"

# 2. --json produces valid JSON
JSON_OUT=$(python3 scripts/audit-backlog.py --json 2>/dev/null)
echo "$JSON_OUT" | python3 -m json.tool > /dev/null 2>&1
assert "--json produces valid JSON" "[ $? -eq 0 ]"

# 3. required fields
python3 -c "
import json, sys
data = json.loads('''$JSON_OUT''')
assert isinstance(data, list), 'not a list'
assert len(data) > 0, 'empty'
for item in data:
    for key in ('id', 'name', 'claimed', 'actual', 'pr', 'issue', 'drift'):
        assert key in item, f'missing {key} in {item[\"id\"]}'
print('ok')
" > /dev/null 2>&1
assert "all items have required fields" "[ $? -eq 0 ]"

# 4. item count >= 27 (26 main + 5 wave0)
ITEM_COUNT=$(echo "$JSON_OUT" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null)
assert "item count >= 31 (27 main + 5 wave0 = 32)" "[ ${ITEM_COUNT:-0} -ge 31 ]"

# 5. drift count = 0 (backlog synced)
DRIFT_COUNT=$(echo "$JSON_OUT" | python3 -c "import json,sys; print(sum(1 for d in json.load(sys.stdin) if d['drift']))" 2>/dev/null)
assert "current drift = 0 (backlog synced)" "[ ${DRIFT_COUNT:-99} -eq 0 ]"

# 6. --help exits 0
python3 scripts/audit-backlog.py --help > /dev/null 2>&1
assert "--help exits 0" "[ $? -eq 0 ]"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
