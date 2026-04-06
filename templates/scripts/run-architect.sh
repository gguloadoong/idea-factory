#!/usr/bin/env bash
# run-architect.sh — Protected File Architect Review
# Generalized from market-dashboard-v5
#
# Reads .protected-files, checks if any are in the current diff,
# runs architect (opus) review if so. Saves artifact to .tmp/.
# create-pr.sh verifies this artifact exists and is fresh.
#
# Usage: bash scripts/run-architect.sh

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

if ! command -v claude &>/dev/null; then
  echo -e "${RED}[architect] claude CLI not installed${NC}"
  exit 1
fi

BRANCH=$(git rev-parse --abbrev-ref HEAD)
SAFE_BRANCH="${BRANCH//\//-}"
HEAD_COMMIT=$(git rev-parse HEAD)
ARTIFACT_DIR=".tmp"
mkdir -p "$ARTIFACT_DIR"
ARTIFACT_FILE="${ARTIFACT_DIR}/architect-review-${SAFE_BRANCH}.md"

echo -e "${GREEN}[architect] branch: ${BRANCH} / commit: ${HEAD_COMMIT:0:8}${NC}"

MERGE_BASE=$(git merge-base origin/main HEAD 2>/dev/null) || {
  echo -e "${RED}[architect] Run: git fetch origin main${NC}"; exit 1;
}

PROTECTED_CONFIG=".protected-files"
if [ ! -f "$PROTECTED_CONFIG" ]; then
  echo -e "${YELLOW}[architect] No .protected-files — nothing to review${NC}"
  { echo "VERDICT: NOT_REQUIRED"; echo "commit: ${HEAD_COMMIT}"; } > "$ARTIFACT_FILE"
  exit 0
fi

# Build diff paths from .protected-files
PATHS=()
while IFS= read -r line; do
  [[ -z "$line" || "$line" == \#* ]] && continue
  PATHS+=("$line")
done < "$PROTECTED_CONFIG"

DIFF_FILE=$(mktemp)
trap 'rm -f "$DIFF_FILE"' EXIT
git diff "$MERGE_BASE" HEAD -- "${PATHS[@]}" > "$DIFF_FILE" 2>&1 || {
  echo -e "${RED}[architect] git diff failed${NC}"; exit 1;
}

DIFF_LINES=$(wc -l < "$DIFF_FILE" | tr -d ' ')
echo -e "${GREEN}[architect] Protected file diff: ${DIFF_LINES} lines${NC}"

if [ "$DIFF_LINES" -eq 0 ]; then
  echo -e "${YELLOW}[architect] No protected file changes — review not required${NC}"
  { echo "VERDICT: NOT_REQUIRED"; echo "commit: ${HEAD_COMMIT}"; echo "reason: no protected file changes"; } > "$ARTIFACT_FILE"
  exit 0
fi

echo -e "${GREEN}[architect] Running architect (opus) review...${NC}"

REVIEW_OUTPUT=$(claude --print "You are a senior software architect.
Review the diff below from a design perspective.

## Review Criteria
1. Design consistency: Does the change align with existing architecture patterns?
2. Edge cases: Any uncovered scenarios?
3. Data flow: Unexpected side effects on connected systems?
4. Synchronization: Missing updates to related files/constants?
5. Performance: Repeated calculations, unnecessary re-renders?

## Output Format (mandatory)
- First line: VERDICT: PASS or VERDICT: BLOCK
- [BLOCK] items: must fix before proceeding
- [WARN] items: recommendations (PR can proceed)
- Include specific file names and line numbers

## Diff
$(cat "$DIFF_FILE")" 2>&1 || true)

if [ -z "$REVIEW_OUTPUT" ]; then
  echo -e "${RED}[architect] No response from claude — manual review required${NC}"
  exit 1
fi

VERDICT=$(echo "$REVIEW_OUTPUT" | grep -oE 'VERDICT:[[:space:]]*(PASS|BLOCK|NOT_REQUIRED)' | awk '{print $2}' | head -1)
[ -z "$VERDICT" ] && VERDICT="UNKNOWN"

if [ "$VERDICT" = "UNKNOWN" ]; then
  echo -e "${RED}[architect] Could not parse VERDICT${NC}"
  exit 1
fi

{ echo "VERDICT: ${VERDICT}"; echo "commit: ${HEAD_COMMIT}"; echo ""; echo "$REVIEW_OUTPUT"; } > "$ARTIFACT_FILE"

echo -e "${GREEN}[architect] Saved: ${ARTIFACT_FILE} / VERDICT: ${VERDICT}${NC}"

if [ "$VERDICT" = "BLOCK" ]; then
  echo -e "${RED}[architect] BLOCK — fix design issues and re-run${NC}"
  exit 1
fi
