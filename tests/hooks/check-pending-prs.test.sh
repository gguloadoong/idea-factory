#!/usr/bin/env bash
# Tests for templates/hooks/check-pending-prs.sh
#
# Verifies:
#   1. gh 없을 때 graceful exit 0, 출력 없음
#   2. git remote 없을 때 graceful exit 0, 출력 없음
#   3. PR 0개일 때 출력 없음
#   4. PR 있을 때 알림 출력 (mock 데이터로)
#   5. PR 번호, 제목 출력 확인
#   6. 시간 표시 확인
#   7. 빈 stdin에도 exit 0
#   8. exit 0 보장 (gh 오류 반환 시에도)

set +e  # assertions track failures manually

HOOK="$(cd "$(dirname "$0")/../.." && pwd)/templates/hooks/check-pending-prs.sh"
if [ ! -f "$HOOK" ]; then
  echo "  FAIL: hook not found at $HOOK"
  exit 1
fi
chmod +x "$HOOK"

TMPDIR_BASE=$(mktemp -d 2>/dev/null || mktemp -d -t idea-factory 2>/dev/null)
if [ -z "$TMPDIR_BASE" ] || [ ! -d "$TMPDIR_BASE" ]; then
  echo "  FAIL: could not create temp directory"
  exit 1
fi
trap 'rm -rf "$TMPDIR_BASE"' EXIT

FAKEBIN="$TMPDIR_BASE/fakebin"
mkdir -p "$FAKEBIN"

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

# ── Helper: create a fake gh that returns given JSON ──────────────────
make_fake_gh() {
  local output="$1"
  local gh_bin="$FAKEBIN/gh_fake"
  # Write JSON to a temp file to avoid quoting issues
  local json_file="$TMPDIR_BASE/pr_output.json"
  printf '%s' "$output" > "$json_file"
  cat > "$gh_bin" <<SHEOF
#!/usr/bin/env bash
cat '$json_file'
SHEOF
  chmod +x "$gh_bin"
  echo "$gh_bin"
}

# ── Helper: create a fake gh that exits non-zero ──────────────────────
make_failing_gh() {
  local gh_bin="$FAKEBIN/gh_fail"
  cat > "$gh_bin" <<'SHEOF'
#!/usr/bin/env bash
echo "error: not in a git repo" >&2
exit 1
SHEOF
  chmod +x "$gh_bin"
  echo "$gh_bin"
}

# ── Helper: create a fake git that succeeds (has remote) ──────────────
make_fake_git_with_remote() {
  cat > "$FAKEBIN/git" <<'SHEOF'
#!/usr/bin/env bash
exit 0
SHEOF
  chmod +x "$FAKEBIN/git"
}

# ── Helper: create a fake git with no remote ─────────────────────────
make_fake_git_no_remote() {
  cat > "$FAKEBIN/git" <<'SHEOF'
#!/usr/bin/env bash
exit 1
SHEOF
  chmod +x "$FAKEBIN/git"
}

# ── Sample PR JSON ────────────────────────────────────────────────────
SAMPLE_PR_JSON='[{"number":42,"title":"chore: v8 인프라 전파","author":{"login":"gguloadoong"},"createdAt":"2020-01-01T00:00:00Z","labels":[]},{"number":43,"title":"feat: backtest 스크립트 추가","author":{"login":"claude-bot"},"createdAt":"2020-01-02T00:00:00Z","labels":[]}]'

EMPTY_PR_JSON='[]'

# ── Test 1: gh 없을 때 graceful exit 0, 출력 없음 ────────────────────
# GH_BIN points to a non-existent binary → command -v fails → skip
make_fake_git_with_remote
OUT=$(PATH="$FAKEBIN:$PATH" GH_BIN="/nonexistent/gh_does_not_exist" bash "$HOOK" 2>/dev/null)
RC=$?
assert_eq "$RC" "0" "T1: exit 0 when gh not found"
assert_empty "$OUT" "T1: no output when gh not found"

# ── Test 2: git remote 없을 때 graceful exit 0, 출력 없음 ────────────
GH_BIN=$(make_fake_gh "$SAMPLE_PR_JSON")
make_fake_git_no_remote
OUT=$(PATH="$FAKEBIN:$PATH" GH_BIN="$GH_BIN" bash "$HOOK" 2>/dev/null)
RC=$?
assert_eq "$RC" "0" "T2: exit 0 when no git remote"
assert_empty "$OUT" "T2: no output when no git remote"

# ── Test 3: PR 0개일 때 출력 없음 ────────────────────────────────────
GH_BIN=$(make_fake_gh "$EMPTY_PR_JSON")
make_fake_git_with_remote
OUT=$(PATH="$FAKEBIN:$PATH" GH_BIN="$GH_BIN" bash "$HOOK" 2>/dev/null)
RC=$?
assert_eq "$RC" "0" "T3: exit 0 when 0 PRs"
assert_empty "$OUT" "T3: no output when 0 PRs"

# ── Test 4: PR 있을 때 알림 출력 ─────────────────────────────────────
GH_BIN=$(make_fake_gh "$SAMPLE_PR_JSON")
make_fake_git_with_remote
OUT=$(PATH="$FAKEBIN:$PATH" GH_BIN="$GH_BIN" bash "$HOOK" 2>/dev/null)
RC=$?
assert_eq "$RC" "0" "T4: exit 0 with PRs present"
assert_contains "$OUT" "PENDING PR REVIEW" "T4: alert header present"
assert_contains "$OUT" "미처리 PR이" "T4: PR count message present"

# ── Test 5: PR 번호, 제목 출력 확인 ──────────────────────────────────
assert_contains "$OUT" "#42" "T5: PR number #42 in output"
assert_contains "$OUT" "chore: v8 인프라 전파" "T5: PR title in output"
assert_contains "$OUT" "#43" "T5: PR number #43 in output"
assert_contains "$OUT" "feat: backtest 스크립트 추가" "T5: PR title #43 in output"

# ── Test 6: 시간 표시 확인 ───────────────────────────────────────────
# createdAt is 2020-01-01 — many years ago, should show N일 전
assert_contains "$OUT" "일 전" "T6: relative time displayed in output"

# ── Test 7: 빈 stdin에도 exit 0 ──────────────────────────────────────
GH_BIN=$(make_fake_gh "$EMPTY_PR_JSON")
make_fake_git_with_remote
echo '' | PATH="$FAKEBIN:$PATH" GH_BIN="$GH_BIN" bash "$HOOK" 2>/dev/null
RC=$?
assert_eq "$RC" "0" "T7: exit 0 with empty stdin"

# ── Test 8: exit 0 보장 — gh가 오류 반환해도 exit 0 ─────────────────
GH_BIN=$(make_failing_gh)
make_fake_git_with_remote
PATH="$FAKEBIN:$PATH" GH_BIN="$GH_BIN" bash "$HOOK" 2>/dev/null
RC=$?
assert_eq "$RC" "0" "T8: exit 0 even when gh exits non-zero"

# ── Summary ───────────────────────────────────────────────────────────
if [ "$FAILED" -gt 0 ]; then
  echo ""
  echo "check-pending-prs: $FAILED assertion(s) failed"
  exit 1
fi

echo "check-pending-prs: 8 assertions passed"
exit 0
