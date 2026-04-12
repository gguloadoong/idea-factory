#!/usr/bin/env bash
# tuning-gate.sh — Advisory gate for parameter tuning PRs
#
# Checks that parameter change commits follow the tuning session protocol:
#   1. Commit message includes a numeric before/after value
#   2. decisions.md was updated in the same PR
#   3. Only one parameter file changed per commit
#
# This script is ADVISORY ONLY. It always exits 0 (idea-factory invariant).
# Violations emit warnings to stderr but do not block.
#
# Usage:
#   bash scripts/tuning-gate.sh                  # checks current PR vs main
#   TUNING_BASE=origin/main bash scripts/tuning-gate.sh
#
# Install as pre-push hook:
#   ln -sf ../../scripts/tuning-gate.sh .git/hooks/pre-push

set +e
trap 'exit 0' ERR EXIT

YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

warn() {
  printf "${YELLOW}[tuning-gate] WARN: %s${NC}\n" "$1" >&2
}

info() {
  printf "${GREEN}[tuning-gate] %s${NC}\n" "$1"
}

# --- Param file detection patterns ---
PARAM_PATTERN='(\.config\.|\.params\.|tuning\.|weights\.|hyperparams?\.|thresholds?\.|settings\.)'

# --- Verify git is available ---
if ! command -v git >/dev/null 2>&1; then
  warn "git not found — tuning gate skipped"
  exit 0
fi

# --- Verify we are in a git repo ---
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  warn "not a git repository — tuning gate skipped"
  exit 0
fi

# --- Determine base ref ---
BASE="${TUNING_BASE:-}"
if [ -z "$BASE" ]; then
  if git rev-parse --verify origin/main >/dev/null 2>&1; then
    BASE="origin/main"
  elif git rev-parse --verify main >/dev/null 2>&1; then
    BASE="main"
  elif git rev-parse --verify origin/master >/dev/null 2>&1; then
    BASE="origin/master"
  else
    warn "cannot determine base branch — tuning gate skipped"
    exit 0
  fi
fi

MERGE_BASE=$(git merge-base "$BASE" HEAD 2>/dev/null || echo "")
if [ -z "$MERGE_BASE" ]; then
  warn "cannot find merge-base with $BASE — tuning gate skipped"
  exit 0
fi

# --- Get list of commits in this PR ---
COMMITS=$(git log --format="%H" "$MERGE_BASE"..HEAD 2>/dev/null || echo "")
if [ -z "$COMMITS" ]; then
  info "no commits ahead of $BASE — nothing to check"
  exit 0
fi

# --- Get all files changed in this PR ---
PR_FILES=$(git diff --name-only "$MERGE_BASE"..HEAD 2>/dev/null || echo "")
if [ -z "$PR_FILES" ]; then
  info "empty diff — nothing to check"
  exit 0
fi

# --- Check if any param files are touched in this PR ---
PARAM_FILES=$(echo "$PR_FILES" | grep -E "$PARAM_PATTERN" || echo "")
if [ -z "$PARAM_FILES" ]; then
  info "no parameter files changed — tuning protocol not required"
  exit 0
fi

info "parameter file(s) detected in PR:"
echo "$PARAM_FILES" | sed 's/^/  /' >&2

VIOLATIONS=0

# --- Check 1: decisions.md updated ---
DECISIONS_CHANGED=$(echo "$PR_FILES" | grep -iE '(^|/)decisions\.md$' || echo "")
if [ -z "$DECISIONS_CHANGED" ]; then
  warn "parameter file(s) changed but decisions.md was not updated"
  warn "  -> Add a tuning ADR entry to decisions.md (see templates/workflows/tuning-session.md)"
  VIOLATIONS=$((VIOLATIONS + 1))
else
  info "decisions.md updated — OK"
fi

# --- Check 2: commit message includes numeric before/after value ---
# Pattern: looks for "X -> Y", "X → Y", "before: X", "from X to Y", or bare numbers like "0.3 -> 0.28"
NUMERIC_PATTERN='([0-9]+\.?[0-9]*[[:space:]]*(->|→|to)[[:space:]]*[0-9]+\.?[0-9]*)|(before:[[:space:]]*[0-9])|(from[[:space:]]+[0-9])'
MISSING_NUMERIC=""
while IFS= read -r commit_hash; do
  [ -z "$commit_hash" ] && continue
  commit_msg=$(git log -1 --format="%s %b" "$commit_hash" 2>/dev/null || echo "")
  param_in_commit=$(git diff-tree --no-commit-id -r --name-only "$commit_hash" 2>/dev/null \
    | grep -E "$PARAM_PATTERN" || echo "")
  if [ -n "$param_in_commit" ]; then
    if ! echo "$commit_msg" | grep -qE "$NUMERIC_PATTERN"; then
      MISSING_NUMERIC="${MISSING_NUMERIC}  ${commit_hash:0:8}: ${commit_msg}\n"
    fi
  fi
done <<< "$COMMITS"

if [ -n "$MISSING_NUMERIC" ]; then
  warn "commit(s) change parameter file(s) but message lacks numeric before/after value:"
  printf "$MISSING_NUMERIC" >&2
  warn "  -> Include e.g. 'rsi_threshold: 30 -> 28' in the commit message"
  VIOLATIONS=$((VIOLATIONS + 1))
else
  info "commit messages include numeric values — OK"
fi

# --- Check 3: only one parameter file per commit ---
MULTI_PARAM_COMMITS=""
while IFS= read -r commit_hash; do
  [ -z "$commit_hash" ] && continue
  param_count=$(git diff-tree --no-commit-id -r --name-only "$commit_hash" 2>/dev/null \
    | grep -cE "$PARAM_PATTERN" || echo "0")
  if [ "$param_count" -gt 1 ]; then
    commit_msg=$(git log -1 --format="%s" "$commit_hash" 2>/dev/null || echo "")
    MULTI_PARAM_COMMITS="${MULTI_PARAM_COMMITS}  ${commit_hash:0:8} (${param_count} param files): ${commit_msg}\n"
  fi
done <<< "$COMMITS"

if [ -n "$MULTI_PARAM_COMMITS" ]; then
  warn "commit(s) change multiple parameter files — one parameter per commit required:"
  printf "$MULTI_PARAM_COMMITS" >&2
  warn "  -> Split into separate commits, one parameter change each"
  VIOLATIONS=$((VIOLATIONS + 1))
else
  info "single parameter per commit — OK"
fi

# --- Summary ---
if [ "$VIOLATIONS" -gt 0 ]; then
  printf "${YELLOW}[tuning-gate] %d advisory violation(s) — see templates/workflows/tuning-session.md${NC}\n" \
    "$VIOLATIONS" >&2
else
  info "tuning protocol checks passed"
fi

exit 0
