#!/usr/bin/env bash
# tests/scripts/check-contract.test.sh — check-contract.sh 단위 테스트
#
# 실행: bash tests/scripts/check-contract.test.sh
# 또는: bash tests/run-all.sh

set +e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/scripts/check-contract.sh"

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
    echo "    output: $(echo "$output" | head -5)"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local label="$1"
  local pattern="$2"
  local output="$3"
  if echo "$output" | grep -qE "$pattern"; then
    echo "  FAIL: $label (pattern '$pattern' unexpectedly found)"
    echo "    output: $(echo "$output" | head -5)"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  fi
}

# --- 임시 디렉터리 설정 ---

TMPDIR_BASE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

make_rules() {
  local file="$1"
  cat > "$file"
}

make_src() {
  local file="$1"
  local content="$2"
  mkdir -p "$(dirname "$file")"
  printf '%s\n' "$content" > "$file"
}

echo "=== check-contract.sh 테스트 ==="

# ─────────────────────────────────────────────
# 1. taCache 패턴 감지
# ─────────────────────────────────────────────
echo ""
echo "-- 1. taCache 패턴 감지 --"
T1="$TMPDIR_BASE/t1"
mkdir -p "$T1/src"
make_src "$T1/src/engine.js" "function compute(taCache) { return taCache.get(); }"
cat > "$T1/rules.yml" <<'EOF'
rules:
  - id: no-ta-cache-param
    description: "taCache 파라미터는 v7에서 제거됨"
    pattern: "taCache"
    files:
      - "*.js"
    action: warn
    contract_ref: "CONTRACT.md #why-no-ta-cache"
EOF

out1=$(bash "$SCRIPT" --rules "$T1/rules.yml" --path "$T1/src" 2>&1)
assert_contains "taCache 위반 감지" "CONTRACT 위반.*no-ta-cache-param" "$out1"
assert_contains "taCache contract_ref 출력" "CONTRACT\.md #why-no-ta-cache" "$out1"

# ─────────────────────────────────────────────
# 2. readFileSync 패턴 감지
# ─────────────────────────────────────────────
echo ""
echo "-- 2. readFileSync 패턴 감지 --"
T2="$TMPDIR_BASE/t2"
mkdir -p "$T2/src"
make_src "$T2/src/util.js" "const data = fs.readFileSync('file.txt', 'utf8');"
cat > "$T2/rules.yml" <<'EOF'
rules:
  - id: no-sync-file-ops
    description: "동기 파일 I/O 금지"
    pattern: "(?:readFileSync|writeFileSync|appendFileSync)"
    files:
      - "*.js"
    action: warn
    contract_ref: "CONTRACT.md #async-io-only"
EOF

out2=$(bash "$SCRIPT" --rules "$T2/rules.yml" --path "$T2/src" 2>&1)
assert_contains "readFileSync 위반 감지" "CONTRACT 위반.*no-sync-file-ops" "$out2"

# ─────────────────────────────────────────────
# 3. 정상 코드에 false positive 없음
# ─────────────────────────────────────────────
echo ""
echo "-- 3. 정상 코드 false positive 없음 --"
T3="$TMPDIR_BASE/t3"
mkdir -p "$T3/src"
make_src "$T3/src/clean.js" "async function readFile(path) { return await fs.promises.readFile(path); }"
cat > "$T3/rules.yml" <<'EOF'
rules:
  - id: no-sync-file-ops
    description: "동기 파일 I/O 금지"
    pattern: "(?:readFileSync|writeFileSync|appendFileSync)"
    files:
      - "*.js"
    action: warn
    contract_ref: "CONTRACT.md #async-io-only"
EOF

out3=$(bash "$SCRIPT" --rules "$T3/rules.yml" --path "$T3/src" 2>&1)
assert_not_contains "정상 코드에 위반 없음" "CONTRACT 위반" "$out3"

# ─────────────────────────────────────────────
# 4. 규칙 파일 없을 때 graceful exit 0
# ─────────────────────────────────────────────
echo ""
echo "-- 4. 규칙 파일 없을 때 exit 0 --"
out4=$(bash "$SCRIPT" --rules "/nonexistent/rules.yml" 2>&1)
code4=$?
assert_exit "규칙 파일 없음 exit 0" 0 $code4
assert_contains "규칙 파일 없음 메시지" "규칙 파일 없음|없으면 건너" "$out4"

# ─────────────────────────────────────────────
# 5. --strict 모드에서 위반 시 exit 1
# ─────────────────────────────────────────────
echo ""
echo "-- 5. --strict 모드 exit 1 --"
T5="$TMPDIR_BASE/t5"
mkdir -p "$T5/src"
make_src "$T5/src/bad.js" "const x = fs.readFileSync('f');"
cat > "$T5/rules.yml" <<'EOF'
rules:
  - id: no-sync-file-ops
    description: "동기 파일 I/O 금지"
    pattern: "readFileSync"
    files:
      - "*.js"
    action: warn
    contract_ref: "CONTRACT.md #async-io-only"
EOF

bash "$SCRIPT" --rules "$T5/rules.yml" --path "$T5/src" --strict >/dev/null 2>&1
code5=$?
assert_exit "--strict 위반 시 exit 1" 1 $code5

# ─────────────────────────────────────────────
# 6. 기본 모드에서 위반 있어도 exit 0
# ─────────────────────────────────────────────
echo ""
echo "-- 6. 기본 모드 exit 0 보장 --"
bash "$SCRIPT" --rules "$T5/rules.yml" --path "$T5/src" >/dev/null 2>&1
code6=$?
assert_exit "기본 모드 위반 있어도 exit 0" 0 $code6

# ─────────────────────────────────────────────
# 7. contract_ref 출력 확인
# ─────────────────────────────────────────────
echo ""
echo "-- 7. contract_ref 출력 확인 --"
T7="$TMPDIR_BASE/t7"
mkdir -p "$T7/src"
make_src "$T7/src/bad.js" "var x = window.foo;"
cat > "$T7/rules.yml" <<'EOF'
rules:
  - id: no-global-state
    description: "전역 상태 변수 금지"
    pattern: "window\\."
    files:
      - "*.js"
    action: warn
    contract_ref: "CONTRACT.md #no-global-state"
EOF

out7=$(bash "$SCRIPT" --rules "$T7/rules.yml" --path "$T7/src" 2>&1)
assert_contains "contract_ref 출력" "#no-global-state" "$out7"

# ─────────────────────────────────────────────
# 8. 빈 규칙 파일 — 위반 없이 exit 0
# ─────────────────────────────────────────────
echo ""
echo "-- 8. 빈 규칙 파일 --"
T8="$TMPDIR_BASE/t8"
mkdir -p "$T8/src"
make_src "$T8/src/any.js" "readFileSync();"
cat > "$T8/rules.yml" <<'EOF'
rules:
EOF

out8=$(bash "$SCRIPT" --rules "$T8/rules.yml" --path "$T8/src" 2>&1)
code8=$?
assert_exit "빈 규칙 파일 exit 0" 0 $code8
assert_not_contains "빈 규칙 파일 위반 없음" "CONTRACT 위반" "$out8"

# ─────────────────────────────────────────────
# 9. files 필터 동작 — 대상 확장자 외 파일은 무시
# ─────────────────────────────────────────────
echo ""
echo "-- 9. files 필터 동작 --"
T9="$TMPDIR_BASE/t9"
mkdir -p "$T9/src"
# .py 파일에 패턴 있어도 files: ["*.js"] 이면 무시
make_src "$T9/src/bad.py" "taCache = True"
cat > "$T9/rules.yml" <<'EOF'
rules:
  - id: no-ta-cache-param
    description: "taCache 파라미터 금지"
    pattern: "taCache"
    files:
      - "*.js"
    action: warn
    contract_ref: "CONTRACT.md #why-no-ta-cache"
EOF

out9=$(bash "$SCRIPT" --rules "$T9/rules.yml" --path "$T9/src" 2>&1)
assert_not_contains "files 필터: .py 파일 무시" "CONTRACT 위반" "$out9"

# ─────────────────────────────────────────────
# 10. --strict 없을 때 항상 exit 0 (위반 다수여도)
# ─────────────────────────────────────────────
echo ""
echo "-- 10. --strict 없으면 항상 exit 0 --"
T10="$TMPDIR_BASE/t10"
mkdir -p "$T10/src"
make_src "$T10/src/a.js" "taCache; readFileSync(); window.x;"
cat > "$T10/rules.yml" <<'EOF'
rules:
  - id: r1
    description: "taCache 금지"
    pattern: "taCache"
    files:
      - "*.js"
    action: warn
    contract_ref: "CONTRACT.md #r1"
  - id: r2
    description: "readFileSync 금지"
    pattern: "readFileSync"
    files:
      - "*.js"
    action: warn
    contract_ref: "CONTRACT.md #r2"
  - id: r3
    description: "window 금지"
    pattern: "window\\."
    files:
      - "*.js"
    action: warn
    contract_ref: "CONTRACT.md #r3"
EOF

bash "$SCRIPT" --rules "$T10/rules.yml" --path "$T10/src" >/dev/null 2>&1
code10=$?
assert_exit "다수 위반도 기본 모드 exit 0" 0 $code10

# ─────────────────────────────────────────────
# 결과 요약
# ─────────────────────────────────────────────
echo ""
echo "=== 결과: PASS=$PASS FAIL=$FAIL ==="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
