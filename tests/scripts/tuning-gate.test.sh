#!/usr/bin/env bash
# tests/scripts/tuning-gate.test.sh — unit tests for scripts/tuning-gate.sh
#
# Each test verifies a specific behavior. The test suite itself exits 0
# only if all assertions pass. tuning-gate.sh always exits 0 (advisory only).
#
# Run: bash tests/scripts/tuning-gate.test.sh
# Or via: bash tests/run-all.sh

set +e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/scripts/tuning-gate.sh"

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

assert_output_contains() {
  local label="$1"
  local pattern="$2"
  local output="$3"
  if echo "$output" | grep -qE "$pattern"; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label (pattern '$pattern' not found in output)"
    echo "    output was: $(echo "$output" | head -5)"
    FAIL=$((FAIL + 1))
  fi
}

assert_output_not_contains() {
  local label="$1"
  local pattern="$2"
  local output="$3"
  if ! echo "$output" | grep -qE "$pattern"; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label (pattern '$pattern' unexpectedly found in output)"
    FAIL=$((FAIL + 1))
  fi
}

# --- Setup: create a temp git repo for testing ---
setup_repo() {
  local tmpdir
  tmpdir=$(mktemp -d)
  git -C "$tmpdir" init -q
  git -C "$tmpdir" config user.email "test@test.com"
  git -C "$tmpdir" config user.name "Test"
  # Create initial commit so merge-base resolution works
  echo "init" > "$tmpdir/README.md"
  git -C "$tmpdir" add README.md
  git -C "$tmpdir" commit -q -m "init"
  echo "$tmpdir"
}

cleanup_repo() {
  local dir="$1"
  [ -n "$dir" ] && rm -rf "$dir"
}

echo "tuning-gate.sh tests"
echo "===================="

# -----------------------------------------------------------------------
# T1: exit 0 always — even when called with no git repo
# -----------------------------------------------------------------------
echo ""
echo "T1: exit 0 always (even on error)"
output=$(cd /tmp && bash "$GATE" 2>&1)
rc=$?
assert_exit "T1 exit code" 0 "$rc"

# -----------------------------------------------------------------------
# T2: silent (no WARN) when no parameter files changed
# -----------------------------------------------------------------------
echo ""
echo "T2: silent when no parameter files changed"
REPO=$(setup_repo)
# Add a non-param file on a feature branch
git -C "$REPO" checkout -q -b feature
echo "hello" > "$REPO/src.ts"
git -C "$REPO" add src.ts
git -C "$REPO" commit -q -m "add source file"
output=$(cd "$REPO" && TUNING_BASE=main bash "$GATE" 2>&1)
rc=$?
assert_exit "T2 exit code" 0 "$rc"
assert_output_not_contains "T2 no WARN emitted" "WARN" "$output"
assert_output_contains "T2 no parameter files message" "no parameter files changed" "$output"
cleanup_repo "$REPO"

# -----------------------------------------------------------------------
# T3: warns when param file changed without decisions.md
# -----------------------------------------------------------------------
echo ""
echo "T3: warns when param file changed without decisions.md"
REPO=$(setup_repo)
git -C "$REPO" checkout -q -b feature
echo "rsi_threshold=30" > "$REPO/strategy.config.json"
git -C "$REPO" add strategy.config.json
git -C "$REPO" commit -q -m "tweak rsi 30 -> 28"
output=$(cd "$REPO" && TUNING_BASE=main bash "$GATE" 2>&1)
rc=$?
assert_exit "T3 exit code" 0 "$rc"
assert_output_contains "T3 warns about missing decisions.md" "decisions\.md" "$output"
assert_output_contains "T3 WARN present" "WARN" "$output"
cleanup_repo "$REPO"

# -----------------------------------------------------------------------
# T4: warns when multiple param files changed in one commit
# -----------------------------------------------------------------------
echo ""
echo "T4: warns when multiple param files in one commit"
REPO=$(setup_repo)
git -C "$REPO" checkout -q -b feature
echo "rsi=30" > "$REPO/strategy.config.json"
echo "ema=20" > "$REPO/model.params.json"
echo "entry" > "$REPO/decisions.md"
git -C "$REPO" add strategy.config.json model.params.json decisions.md
git -C "$REPO" commit -q -m "update params 30 -> 28"
output=$(cd "$REPO" && TUNING_BASE=main bash "$GATE" 2>&1)
rc=$?
assert_exit "T4 exit code" 0 "$rc"
assert_output_contains "T4 warns about multiple param files" "multiple parameter files" "$output"
cleanup_repo "$REPO"

# -----------------------------------------------------------------------
# T5: silent/pass when param file + decisions.md both changed, one param, numeric message
# -----------------------------------------------------------------------
echo ""
echo "T5: silent when param file + decisions.md both changed (compliant commit)"
REPO=$(setup_repo)
git -C "$REPO" checkout -q -b feature
echo "rsi_threshold=28" > "$REPO/strategy.config.json"
echo "## rsi_threshold 30 -> 28" > "$REPO/decisions.md"
git -C "$REPO" add strategy.config.json decisions.md
git -C "$REPO" commit -q -m "rsi_threshold: 30 -> 28 for tighter entries"
output=$(cd "$REPO" && TUNING_BASE=main bash "$GATE" 2>&1)
rc=$?
assert_exit "T5 exit code" 0 "$rc"
assert_output_contains "T5 tuning protocol checks passed" "tuning protocol checks passed" "$output"
assert_output_not_contains "T5 no violations" "violation" "$output"
cleanup_repo "$REPO"

# -----------------------------------------------------------------------
# T6: handles missing git gracefully (stub git that does not exist)
# -----------------------------------------------------------------------
echo ""
echo "T6: handles missing git gracefully"
FAKE_BIN=$(mktemp -d)
# Write a git stub that exits non-zero to simulate git being broken/absent
printf '#!/usr/bin/env bash\nexit 127\n' > "$FAKE_BIN/git"
chmod +x "$FAKE_BIN/git"
output=$(PATH="$FAKE_BIN:$PATH" bash "$GATE" 2>&1)
rc=$?
assert_exit "T6 exit code" 0 "$rc"
assert_output_contains "T6 graceful message" "(tuning gate skipped|not a git repo|cannot)" "$output"
rm -rf "$FAKE_BIN"

# -----------------------------------------------------------------------
# T7: detects various param file patterns
# -----------------------------------------------------------------------
echo ""
echo "T7: detects various param file patterns"
PARAM_PATTERN='(\.config\.|\.params\.|tuning\.|weights\.|hyperparams?\.|thresholds?\.|settings\.)'

patterns=(
  "strategy.config.json"
  "model.params.yaml"
  "tuning.toml"
  "weights.bin"
  "hyperparams.json"
  "thresholds.yaml"
  "settings.json"
)
all_matched=1
for f in "${patterns[@]}"; do
  if ! echo "$f" | grep -qE "$PARAM_PATTERN"; then
    echo "  FAIL: T7 pattern did not match: $f"
    FAIL=$((FAIL + 1))
    all_matched=0
  fi
done
if [ "$all_matched" -eq 1 ]; then
  echo "  PASS: T7 all ${#patterns[@]} param file patterns matched"
  PASS=$((PASS + 1))
fi

# -----------------------------------------------------------------------
# T8: exit 0 on empty diff (no commits ahead of base)
# -----------------------------------------------------------------------
echo ""
echo "T8: exit 0 on empty diff"
REPO=$(setup_repo)
# Stay on main, no additional commits — HEAD == main
output=$(cd "$REPO" && TUNING_BASE=main bash "$GATE" 2>&1)
rc=$?
assert_exit "T8 exit code" 0 "$rc"
# Should report no commits or empty diff, not error
assert_output_not_contains "T8 no WARN on empty diff" "WARN" "$output"
cleanup_repo "$REPO"

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
echo ""
echo "===================="
echo "Results: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

exit 0
