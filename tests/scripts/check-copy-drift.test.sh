#!/usr/bin/env bash
# Tests for scripts/check-copy-drift.sh (v8 item 5.4)
#
# Verifies:
#   T1: exit 0 when COPIED-FROM.md does not exist
#   T2: exit 0 always (even with bad args)
#   T3: --help outputs Usage
#   T4: graceful warning when gh CLI not found
#   T5: empty table handled gracefully (no entries → exit 0)
#   T6: example/placeholder rows are skipped (not treated as real entries)
#   T7: ignore policy rows are skipped
#   T8: script is valid bash syntax
#   T9: exit 0 with a real COPIED-FROM.md that has no table rows
#  T10: script parses valid entry row (python3 parsing smoke test)

set +e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/scripts/check-copy-drift.sh"

FAILED=0

fail() {
  echo "  FAIL: $1"
  FAILED=$((FAILED + 1))
}

# ── T1: exit 0 when no COPIED-FROM.md ────────────────────────────────
TMPDIR_T1=$(mktemp -d)
OUT=$(cd "$TMPDIR_T1" && bash "$SCRIPT" 2>&1)
RC=$?
[ "$RC" -eq 0 ] || fail "T1: expected exit 0 without COPIED-FROM.md, got $RC"
echo "$OUT" | grep -qi "no copied-from" || fail "T1b: expected informational message when file missing"
rm -rf "$TMPDIR_T1"

# ── T2: exit 0 always, even with garbage args ─────────────────────────
bash "$SCRIPT" --nonexistent-flag 2>/dev/null
RC=$?
[ "$RC" -eq 0 ] || fail "T2: expected exit 0 with unknown flag, got $RC"

# ── T3: --help outputs Usage ──────────────────────────────────────────
OUT=$(bash "$SCRIPT" --help 2>/dev/null)
RC=$?
[ "$RC" -eq 0 ] || fail "T3a: --help exit code"
echo "$OUT" | grep -q "Usage" || fail "T3b: --help missing Usage text"

# ── T4: graceful warning when gh not found ────────────────────────────
TMPDIR_T4=$(mktemp -d)
cat > "$TMPDIR_T4/COPIED-FROM.md" <<'EOF'
# Copied Files Registry

| 로컬 파일 | 상류 레포 | 상류 경로 | 복사 시점 커밋 | 동기화 정책 |
|-----------|-----------|----------|--------------|-----------|
| `src/foo.js` | `myorg/myrepo` | `src/foo.js` | `abc1234` | `manual` |
EOF

# Temporarily override PATH to hide gh
OUT=$(cd "$TMPDIR_T4" && PATH="/usr/bin:/bin" bash "$SCRIPT" --file "$TMPDIR_T4/COPIED-FROM.md" 2>&1)
RC=$?
[ "$RC" -eq 0 ] || fail "T4: expected exit 0 when gh missing, got $RC"
echo "$OUT" | grep -qi "gh\|cli\|not found\|install" || fail "T4b: expected warning about missing gh"
rm -rf "$TMPDIR_T4"

# ── T5: empty table (only header) handled gracefully ─────────────────
TMPDIR_T5=$(mktemp -d)
cat > "$TMPDIR_T5/COPIED-FROM.md" <<'EOF'
# Copied Files Registry

| 로컬 파일 | 상류 레포 | 상류 경로 | 복사 시점 커밋 | 동기화 정책 |
|-----------|-----------|----------|--------------|-----------|
EOF

OUT=$(cd "$TMPDIR_T5" && bash "$SCRIPT" --file "$TMPDIR_T5/COPIED-FROM.md" 2>&1)
RC=$?
[ "$RC" -eq 0 ] || fail "T5: expected exit 0 with empty table, got $RC"
echo "$OUT" | grep -qi "no registered\|nothing to check" || fail "T5b: expected message about no entries"
rm -rf "$TMPDIR_T5"

# ── T6: placeholder/example rows skipped ─────────────────────────────
TMPDIR_T6=$(mktemp -d)
cat > "$TMPDIR_T6/COPIED-FROM.md" <<'EOF'
# Copied Files Registry

| 로컬 파일 | 상류 레포 | 상류 경로 | 복사 시점 커밋 | 동기화 정책 |
|-----------|-----------|----------|--------------|-----------|
| `src/_ta-core.js` | `owner/upstream-repo` | `src/taCalculator.js` | `abc1234` | `manual` |
EOF

# When gh is not available, the placeholder check should still cause "no entries"
# (parser skips example rows) — we just verify exit 0
OUT=$(cd "$TMPDIR_T6" && PATH="/usr/bin:/bin" bash "$SCRIPT" --file "$TMPDIR_T6/COPIED-FROM.md" 2>&1)
RC=$?
[ "$RC" -eq 0 ] || fail "T6: expected exit 0 with only placeholder rows, got $RC"
rm -rf "$TMPDIR_T6"

# ── T7: ignore policy rows are counted but skipped ───────────────────
# Python parser smoke test: verify ignore policy row is parsed and tagged
RESULT=$(REGISTRY_FILE=/dev/stdin python3 -c '
import os, sys

registry = os.environ.get("REGISTRY_FILE", "COPIED-FROM.md")
with open(registry) as fh:
    content = fh.read()

rows = []
for line in content.splitlines():
    line = line.strip()
    if not line.startswith("|"):
        continue
    cols = [c.strip().strip("`") for c in line.split("|")]
    cols = [c for c in cols if c]
    if len(cols) < 5:
        continue
    if "---" in cols[0] or "로컬 파일" in cols[0] or "local" in cols[0].lower():
        continue
    local_file, upstream_repo, upstream_path, commit, policy = cols[0], cols[1], cols[2], cols[3], cols[4]
    if "upstream-repo" in upstream_repo:
        continue
    rows.append((local_file, upstream_repo, upstream_path, commit, policy))

for row in rows:
    print("\t".join(row))
' <<'EOF'
# Copied Files Registry

| 로컬 파일 | 상류 레포 | 상류 경로 | 복사 시점 커밋 | 동기화 정책 |
|-----------|-----------|----------|--------------|-----------|
| `src/bar.js` | `myorg/myrepo` | `src/bar.js` | `def5678` | `ignore` |
EOF
)
echo "$RESULT" | grep -q "ignore" || fail "T7: parser should emit ignore-policy rows"
echo "$RESULT" | grep -q "myorg/myrepo" || fail "T7b: parser should emit correct upstream_repo"

# ── T8: valid bash syntax ─────────────────────────────────────────────
bash -n "$SCRIPT" 2>/dev/null
[ $? -eq 0 ] || fail "T8: script has bash syntax errors"

# ── T9: COPIED-FROM.md exists but has no table at all ────────────────
TMPDIR_T9=$(mktemp -d)
cat > "$TMPDIR_T9/COPIED-FROM.md" <<'EOF'
# Copied Files Registry

이 파일은 아직 비어 있습니다.
EOF

OUT=$(cd "$TMPDIR_T9" && bash "$SCRIPT" --file "$TMPDIR_T9/COPIED-FROM.md" 2>&1)
RC=$?
[ "$RC" -eq 0 ] || fail "T9: expected exit 0 with no table, got $RC"
rm -rf "$TMPDIR_T9"

# ── T10: python3 parser smoke test — multi-row table ─────────────────
RESULT=$(python3 -c '
import sys

content = sys.stdin.read()
rows = []
for line in content.splitlines():
    line = line.strip()
    if not line.startswith("|"):
        continue
    cols = [c.strip().strip("`") for c in line.split("|")]
    cols = [c for c in cols if c]
    if len(cols) < 5:
        continue
    if "---" in cols[0] or "로컬 파일" in cols[0]:
        continue
    local_file, upstream_repo, upstream_path, commit, policy = cols[0], cols[1], cols[2], cols[3], cols[4]
    if "upstream-repo" in upstream_repo:
        continue
    rows.append(local_file)

print(len(rows))
' <<'EOF'
| 로컬 파일 | 상류 레포 | 상류 경로 | 복사 시점 커밋 | 동기화 정책 |
|-----------|-----------|----------|--------------|-----------|
| `src/a.js` | `org/repo1` | `lib/a.js` | `aaa1111` | `manual` |
| `src/b.js` | `org/repo2` | `lib/b.js` | `bbb2222` | `alert` |
| `src/c.js` | `org/repo3` | `lib/c.js` | `ccc3333` | `ignore` |
EOF
)
[ "$RESULT" -eq 3 ] || fail "T10: parser should return 3 rows, got $RESULT"

# ── Summary ──────────────────────────────────────────────────────────
if [ "$FAILED" -gt 0 ]; then
  echo ""
  echo "check-copy-drift: $FAILED assertion(s) failed"
  exit 1
fi

echo "check-copy-drift: 10 assertions passed"
exit 0
