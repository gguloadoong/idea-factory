#!/usr/bin/env bash
# Tests for scripts/sync-downstream.sh + scripts/sync-lib.py (v8 item 7.4)
#
# Verifies:
#   1. Exit 0 always
#   2. --help works
#   3. Fails gracefully without registry
#   4. Python syntax valid
#   5. Registry JSON valid
#   6. Manifest JSON valid
#   7. Managed + computed file counts match
#   8. All managed src files exist in templates/

set +e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/scripts/sync-downstream.sh"
LIB="$ROOT/scripts/sync-lib.py"

FAILED=0

fail() {
  echo "  FAIL: $1"
  FAILED=$((FAILED + 1))
}

# ── Test 1: exit 0 always ───────────────────────────────────────
bash "$SCRIPT" --check --repo nonexistent-repo 2>/dev/null
RC=$?
[ "$RC" -eq 0 ] || fail "T1: expected exit 0, got $RC"

# ── Test 2: --help works ────────────────────────────────────────
OUT=$(bash "$SCRIPT" --help 2>/dev/null)
RC=$?
[ "$RC" -eq 0 ] || fail "T2a: --help exit code"
echo "$OUT" | grep -q "Usage" || fail "T2b: --help missing Usage text"

# ── Test 3: graceful without registry ────────────────────────────
TMPDIR=$(mktemp -d)
cp "$SCRIPT" "$TMPDIR/sync-downstream.sh"
# Run from dir without registry
OUT=$(cd "$TMPDIR" && bash sync-downstream.sh 2>&1)
RC=$?
[ "$RC" -eq 0 ] || fail "T3: expected exit 0 without registry, got $RC"
rm -rf "$TMPDIR"

# ── Test 4: Python syntax valid ──────────────────────────────────
python3 -c "import ast; ast.parse(open('$LIB').read())" 2>/dev/null
[ $? -eq 0 ] || fail "T4: sync-lib.py syntax error"

# ── Test 5: Registry JSON valid ──────────────────────────────────
python3 -c "import json; d=json.load(open('$ROOT/downstream-registry.json')); assert 'repos' in d; assert len(d['repos']) > 0" 2>/dev/null
[ $? -eq 0 ] || fail "T5: downstream-registry.json invalid"

# ── Test 6: Manifest JSON valid ──────────────────────────────────
python3 -c "import json; d=json.load(open('$ROOT/sync-manifest.json')); assert 'managed' in d; assert 'computed' in d; assert 'customized' in d" 2>/dev/null
[ $? -eq 0 ] || fail "T6: sync-manifest.json invalid"

# ── Test 7: File counts match ────────────────────────────────────
MANAGED=$(python3 -c "import json; print(len(json.load(open('$ROOT/sync-manifest.json'))['managed']))")
COMPUTED=$(python3 -c "import json; print(len(json.load(open('$ROOT/sync-manifest.json'))['computed']))")
TOTAL=$((MANAGED + COMPUTED))
[ "$TOTAL" -ge 15 ] || fail "T7: expected 15+ managed+computed files, got $TOTAL"

# ── Test 8: All managed src files exist ──────────────────────────
MISSING_SRC=0
python3 -c "
import json, os, sys
manifest = json.load(open('$ROOT/sync-manifest.json'))
root = '$ROOT'
missing = []
for entry in manifest['managed']:
    path = os.path.join(root, entry['src'])
    if not os.path.exists(path):
        missing.append(entry['src'])
if missing:
    for m in missing:
        print(f'  missing: {m}')
    sys.exit(1)
" 2>/dev/null
[ $? -eq 0 ] || fail "T8: some managed src files don't exist in templates/"

# ── Test 9: Registry repos have valid type ───────────────────────
python3 -c "
import json, sys
reg = json.load(open('$ROOT/downstream-registry.json'))
valid_types = {'web-app', 'cron-bot', 'trading', 'payment'}
for repo in reg['repos']:
    if repo.get('type') not in valid_types:
        print(f'  invalid type: {repo[\"name\"]} -> {repo.get(\"type\")}')
        sys.exit(1)
" 2>/dev/null
[ $? -eq 0 ] || fail "T9: some repos have invalid project type"

# ── Test 10: merge-settings.sh works for all registry types ─────
TYPES=$(python3 -c "import json; print(' '.join(set(r['type'] for r in json.load(open('$ROOT/downstream-registry.json'))['repos'])))")
for t in $TYPES; do
  OUT=$(bash "$ROOT/scripts/merge-settings.sh" "$t" 2>/dev/null)
  RC=$?
  [ "$RC" -eq 0 ] || fail "T10: merge-settings.sh failed for type $t"
done

# ── Summary ──────────────────────────────────────────────────────
if [ "$FAILED" -gt 0 ]; then
  echo ""
  echo "sync-downstream: $FAILED assertion(s) failed"
  exit 1
fi

echo "sync-downstream: 10 assertions passed"
exit 0
