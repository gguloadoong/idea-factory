#!/usr/bin/env bash
# tests/scripts/runtime-ratchet.test.sh — unit tests for runtime-ratchet.sh
#
# Run: bash tests/scripts/runtime-ratchet.test.sh
# Or via: bash tests/run-all.sh
#
# All assertions use exit-code 0; the ratchet script itself always exits 0.

set +e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/templates/scripts/runtime-ratchet.sh"

PASS=0
FAIL=0

# ── Helpers ───────────────────────────────────────────────────────────────────

assert_exit() {
  local label="$1" expected="$2" actual="$3"
  if [ "$actual" -eq "$expected" ]; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label (expected exit $expected, got $actual)"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local label="$1" pattern="$2" output="$3"
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
  local label="$1" pattern="$2" output="$3"
  if ! echo "$output" | grep -qE "$pattern"; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label (unexpected pattern '$pattern' found)"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_exists() {
  local label="$1" file="$2"
  if [ -f "$file" ]; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label (file '$file' does not exist)"
    FAIL=$((FAIL + 1))
  fi
}

assert_valid_json() {
  local label="$1" file="$2"
  if python3 -c "import json, sys; json.load(open('$file'))" 2>/dev/null; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label (file '$file' is not valid JSON)"
    FAIL=$((FAIL + 1))
  fi
}

# Create a temp dir with a minimal .ratchet.yml
setup_dir() {
  local tmpdir
  tmpdir=$(mktemp -d)
  echo "$tmpdir"
}

cleanup_dir() {
  local dir="$1"
  [ -n "$dir" ] && rm -rf "$dir"
}

make_config() {
  local dir="$1"
  cat > "$dir/.ratchet.yml" <<'EOF'
metrics:
  - name: error_rate
    source: "echo 0.02"
    threshold: 0.05
    direction: lower_is_better

  - name: success_rate
    source: "echo 0.98"
    threshold: 0.05
    direction: higher_is_better
EOF
}

echo "runtime-ratchet.sh tests"
echo "========================"

# ─────────────────────────────────────────────────────────────────────────────
# T1: .ratchet.yml 없을 때 graceful exit 0
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "T1: missing config — graceful exit 0"
DIR=$(setup_dir)
output=$(cd "$DIR" && bash "$SCRIPT" --config .ratchet.yml --check 2>&1)
rc=$?
assert_exit "T1 exit code" 0 "$rc"
assert_contains "T1 warns about missing config" "not found|skipping" "$output"
cleanup_dir "$DIR"

# ─────────────────────────────────────────────────────────────────────────────
# T2: --check 모드 기본 동작 (기준선 없음 → skip 메시지)
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "T2: --check with no baseline — reports skip"
DIR=$(setup_dir)
make_config "$DIR"
output=$(cd "$DIR" && bash "$SCRIPT" --config .ratchet.yml --check --allow-exec 2>&1)
rc=$?
assert_exit "T2 exit code" 0 "$rc"
assert_contains "T2 mentions run --update" "update" "$output"
cleanup_dir "$DIR"

# ─────────────────────────────────────────────────────────────────────────────
# T3: --update 모드로 기준선 생성
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "T3: --update creates baseline file"
DIR=$(setup_dir)
make_config "$DIR"
output=$(cd "$DIR" && bash "$SCRIPT" --config .ratchet.yml --update --allow-exec 2>&1)
rc=$?
assert_exit "T3 exit code" 0 "$rc"
assert_file_exists "T3 baseline file created" "$DIR/.ratchet-baseline.json"
assert_valid_json "T3 baseline is valid JSON" "$DIR/.ratchet-baseline.json"
cleanup_dir "$DIR"

# ─────────────────────────────────────────────────────────────────────────────
# T4: 기준선 대비 회귀 감지 (lower_is_better — value increases past threshold)
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "T4: regression detected when lower_is_better metric worsens"
DIR=$(setup_dir)
# Baseline: error_rate=0.02, success_rate=0.98
cat > "$DIR/.ratchet.yml" <<'EOF'
metrics:
  - name: error_rate
    source: "echo 0.99"
    threshold: 0.05
    direction: lower_is_better
EOF
# Write baseline with good value
echo '{"error_rate":0.02}' > "$DIR/.ratchet-baseline.json"
output=$(cd "$DIR" && bash "$SCRIPT" --config .ratchet.yml --check --allow-exec 2>&1)
rc=$?
assert_exit "T4 exit code" 0 "$rc"
assert_contains "T4 FAIL/regression detected" "REGRESSION|FAIL" "$output"
cleanup_dir "$DIR"

# ─────────────────────────────────────────────────────────────────────────────
# T5: 기준선 대비 개선 시 통과 (lower_is_better — value decreases)
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "T5: improvement passes (lower_is_better)"
DIR=$(setup_dir)
cat > "$DIR/.ratchet.yml" <<'EOF'
metrics:
  - name: error_rate
    source: "echo 0.01"
    threshold: 0.05
    direction: lower_is_better
EOF
echo '{"error_rate":0.02}' > "$DIR/.ratchet-baseline.json"
output=$(cd "$DIR" && bash "$SCRIPT" --config .ratchet.yml --check --allow-exec 2>&1)
rc=$?
assert_exit "T5 exit code" 0 "$rc"
assert_contains "T5 PASS reported" "PASS" "$output"
assert_not_contains "T5 no REGRESSION" "REGRESSION" "$output"
cleanup_dir "$DIR"

# ─────────────────────────────────────────────────────────────────────────────
# T6: higher_is_better 방향 — 값 하락 시 회귀 감지
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "T6: regression detected when higher_is_better metric drops"
DIR=$(setup_dir)
cat > "$DIR/.ratchet.yml" <<'EOF'
metrics:
  - name: success_rate
    source: "echo 0.50"
    threshold: 0.05
    direction: higher_is_better
EOF
echo '{"success_rate":0.98}' > "$DIR/.ratchet-baseline.json"
output=$(cd "$DIR" && bash "$SCRIPT" --config .ratchet.yml --check --allow-exec 2>&1)
rc=$?
assert_exit "T6 exit code" 0 "$rc"
assert_contains "T6 REGRESSION detected" "REGRESSION|FAIL" "$output"
cleanup_dir "$DIR"

# ─────────────────────────────────────────────────────────────────────────────
# T7: --allow-exec 없이 source 실행 차단
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "T7: source commands blocked without --allow-exec"
DIR=$(setup_dir)
make_config "$DIR"
echo '{"error_rate":0.02,"success_rate":0.98}' > "$DIR/.ratchet-baseline.json"
output=$(cd "$DIR" && bash "$SCRIPT" --config .ratchet.yml --check 2>&1)
rc=$?
assert_exit "T7 exit code" 0 "$rc"
assert_contains "T7 blocked warning" "blocked|allow-exec" "$output"
cleanup_dir "$DIR"

# ─────────────────────────────────────────────────────────────────────────────
# T8: 빈 config (metrics 섹션 없음) — graceful 처리
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "T8: empty config graceful handling"
DIR=$(setup_dir)
echo "# empty config" > "$DIR/.ratchet.yml"
output=$(cd "$DIR" && bash "$SCRIPT" --config .ratchet.yml --check --allow-exec 2>&1)
rc=$?
assert_exit "T8 exit code" 0 "$rc"
assert_contains "T8 no-metrics message" "No metrics|nothing to do" "$output"
cleanup_dir "$DIR"

# ─────────────────────────────────────────────────────────────────────────────
# T9: exit 0 보장 — 악의적 source 명령도 exit 0
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "T9: exit 0 guaranteed even when source command fails"
DIR=$(setup_dir)
cat > "$DIR/.ratchet.yml" <<'EOF'
metrics:
  - name: bad_metric
    source: "exit 99"
    threshold: 0.05
    direction: lower_is_better
EOF
echo '{"bad_metric":0.5}' > "$DIR/.ratchet-baseline.json"
output=$(cd "$DIR" && bash "$SCRIPT" --config .ratchet.yml --check --allow-exec 2>&1)
rc=$?
assert_exit "T9 exit code always 0" 0 "$rc"
cleanup_dir "$DIR"

# ─────────────────────────────────────────────────────────────────────────────
# T10: 기준선 파일이 유효한 JSON인지 확인 (--update 후)
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "T10: baseline file is valid JSON after --update"
DIR=$(setup_dir)
cat > "$DIR/.ratchet.yml" <<'EOF'
metrics:
  - name: winrate
    source: "echo 0.65"
    threshold: 0.05
    direction: higher_is_better

  - name: drawdown
    source: "echo 0.10"
    threshold: 0.10
    direction: lower_is_better
EOF
cd "$DIR" && bash "$SCRIPT" --config .ratchet.yml --update --allow-exec > /dev/null 2>&1
assert_file_exists "T10 baseline exists" "$DIR/.ratchet-baseline.json"
assert_valid_json "T10 baseline valid JSON" "$DIR/.ratchet-baseline.json"
cleanup_dir "$DIR"

# ─────────────────────────────────────────────────────────────────────────────
# T11: higher_is_better — 값 상승 시 통과
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "T11: improvement passes (higher_is_better)"
DIR=$(setup_dir)
cat > "$DIR/.ratchet.yml" <<'EOF'
metrics:
  - name: success_rate
    source: "echo 0.99"
    threshold: 0.05
    direction: higher_is_better
EOF
echo '{"success_rate":0.95}' > "$DIR/.ratchet-baseline.json"
output=$(cd "$DIR" && bash "$SCRIPT" --config .ratchet.yml --check --allow-exec 2>&1)
rc=$?
assert_exit "T11 exit code" 0 "$rc"
assert_contains "T11 PASS reported" "PASS" "$output"
assert_not_contains "T11 no REGRESSION" "REGRESSION" "$output"
cleanup_dir "$DIR"

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "========================"
echo "Results: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
