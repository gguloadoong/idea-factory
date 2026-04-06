#!/usr/bin/env bash
# update-project-docs.sh — Auto-Update Project Docs on PR
# Generalized from market-dashboard-v5
#
# Checks:
#   1. CONTRACT.md — does it need updating after component changes?
#   2. decisions.md — should a new ADR be added?
#   3. README.md — does the features table need updating?
#
# Usage: bash scripts/update-project-docs.sh
# Called automatically by create-pr.sh (step 4.5)

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

BRANCH=$(git rev-parse --abbrev-ref HEAD)

echo -e "${BLUE}[docs] Project docs auto-update${NC}"

# --- Gather info ---
COMMITS=$(git log origin/main..HEAD --oneline 2>/dev/null | head -10 || echo "(no commits)")
HAS_FEAT=$(echo "$COMMITS" | grep -c "feat:" || true)
HAS_FIX=$(echo "$COMMITS" | grep -c "fix:" || true)

# --- 1. CONTRACT.md check ---
echo -e "${BLUE}[docs] Checking CONTRACT.md...${NC}"
CONTRACT_FILES=$(find src/ -name "CONTRACT.md" 2>/dev/null || true)
if [ -n "$CONTRACT_FILES" ]; then
  # Check if any src/ files were added or deleted
  ADDED=$(git diff origin/main..HEAD --diff-filter=A --name-only -- 'src/' 2>/dev/null | head -5 || true)
  DELETED=$(git diff origin/main..HEAD --diff-filter=D --name-only -- 'src/' 2>/dev/null | head -5 || true)
  if [ -n "$ADDED" ] || [ -n "$DELETED" ]; then
    echo -e "${YELLOW}[docs] src/ files added/deleted — update CONTRACT.md${NC}"
    [ -n "$ADDED" ] && echo "  Added: $ADDED"
    [ -n "$DELETED" ] && echo "  Deleted: $DELETED"
  else
    echo -e "${GREEN}[docs] CONTRACT.md — no structural changes${NC}"
  fi
else
  echo -e "${GREEN}[docs] No CONTRACT.md found — skipping${NC}"
fi

# --- 2. decisions.md ADR check ---
echo -e "${BLUE}[docs] Checking decisions.md...${NC}"
if [ -f ".project/decisions.md" ]; then
  # Suggest ADR for architectural changes
  ARCH_CHANGES=$(echo "$COMMITS" | grep -cE "^[a-f0-9]+ (feat|refactor):" || true)
  if [ "$ARCH_CHANGES" -gt 0 ]; then
    echo -e "${YELLOW}[docs] ${ARCH_CHANGES} feat/refactor commits — consider adding ADR to decisions.md${NC}"
  fi
fi

# --- 3. README.md features table ---
if [ "$HAS_FEAT" -gt 0 ]; then
  echo -e "${YELLOW}[docs] ${HAS_FEAT} feat: commits detected — check README.md features table${NC}"
fi

echo -e "${GREEN}[docs] Doc update check complete${NC}"
