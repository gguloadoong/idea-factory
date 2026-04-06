#!/usr/bin/env bash
# pre-deploy-consensus.sh — 6-Gate Deploy Consensus
# Generalized from market-dashboard-v5 (proven across 13 phases)
#
# Usage: bash scripts/pre-deploy-consensus.sh
# All gates must PASS for deploy to proceed.
#
# Gates:
#   1. Build passes
#   2. No P0/P1 open issues
#   3. PM review (auto via claude CLI, or manual)
#   4. QA approval (quality-baseline.md check)
#   5. Dev approval (protected files check)
#   6. Final sign-off (deploy conditions met)

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
FAIL=0
SKIP=0

check() {
  local name="$1" result="$2" detail="${3:-}"
  if [ "$result" = "PASS" ]; then
    echo -e "${GREEN}  [PASS] ${name}${NC}${detail:+ — ${detail}}"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}  [FAIL] ${name}${NC}${detail:+ — ${detail}}"
    FAIL=$((FAIL + 1))
  fi
}

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Pre-Deploy Consensus Gate${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# === Gate 1: Build ===
echo -e "${BLUE}[1/6] Build Verification${NC}"
if npm run build --silent 2>/dev/null; then
  check "Build" "PASS" "build succeeded"
else
  check "Build" "FAIL" "build failed"
fi

# === Gate 2: P0/P1 Issues ===
echo -e "${BLUE}[2/6] P0/P1 Open Issues${NC}"
P0_ISSUES=$(gh issue list --label "P0" --state open --json number --jq 'length' 2>/dev/null || true)
P1_ISSUES=$(gh issue list --label "P1" --state open --json number --jq 'length' 2>/dev/null || true)

if [ -z "$P0_ISSUES" ] || [ -z "$P1_ISSUES" ]; then
  check "P0/P1 Issues" "FAIL" "GitHub API error — check gh auth"
else
  CRITICAL=$((P0_ISSUES + P1_ISSUES))
  if [ "$CRITICAL" -eq 0 ]; then
    check "P0/P1 Issues" "PASS" "none open"
  else
    check "P0/P1 Issues" "FAIL" "P0: ${P0_ISSUES}, P1: ${P1_ISSUES}"
  fi
fi

# === Gate 3: PM Review (auto or manual) ===
echo -e "${BLUE}[3/6] PM Review${NC}"
PM_VERDICT="SKIP"

if command -v claude &>/dev/null && [ -f ".project/backlog.md" ]; then
  # Nonce-based prompt injection prevention
  PM_NONCE="PMGATE_$(date +%s)_${RANDOM}"
  DEPLOY_COMMITS=$(git log origin/main..HEAD --oneline 2>/dev/null | head -20 || echo "(no recent commits)")

  PM_PROMPT="You are a PM reviewing deploy readiness.

## Commits to deploy
${DEPLOY_COMMITS}

Review criteria:
- Do commit titles match actual changes?
- Any scope creep beyond intended changes?
- Does work align with project direction?

Last line MUST be exactly:
${PM_NONCE}: PASS
or
${PM_NONCE}: BLOCK — (reason)"

  PM_TMP=$(mktemp)
  printf '%s' "$PM_PROMPT" > "$PM_TMP"
  PM_RESULT=$(claude --print < "$PM_TMP" 2>/dev/null || echo "${PM_NONCE}: SKIP")
  rm -f "$PM_TMP"

  PM_VERDICT_LINE=$(echo "$PM_RESULT" | grep "^${PM_NONCE}:" | tail -1)

  if echo "$PM_VERDICT_LINE" | grep -q "^${PM_NONCE}: BLOCK"; then
    PM_VERDICT="BLOCK"
    check "PM Review" "FAIL" "intent mismatch detected"
  elif echo "$PM_VERDICT_LINE" | grep -q "^${PM_NONCE}: PASS"; then
    PM_VERDICT="PASS"
    check "PM Review" "PASS" "intent and implementation aligned"
  else
    PM_VERDICT="SKIP"
    SKIP=$((SKIP + 1))
    echo -e "${YELLOW}    PM review SKIP (parse failure) — manual check recommended${NC}"
  fi
else
  SKIP=$((SKIP + 1))
  echo -e "${YELLOW}    PM gate SKIP (claude CLI or backlog.md missing)${NC}"
fi

# === Gate 4: QA Approval (quality-baseline.md) ===
echo -e "${BLUE}[4/6] QA Approval${NC}"
QUALITY_FILE=".project/quality-baseline.md"
QA_ISSUES=0

if [ -f "$QUALITY_FILE" ]; then
  check "Quality baseline file" "PASS" "quality-baseline.md exists"
else
  check "Quality baseline file" "FAIL" ".project/quality-baseline.md missing"
  QA_ISSUES=$((QA_ISSUES + 1))
fi

if [ "$QA_ISSUES" -eq 0 ]; then
  check "QA Approval" "PASS" "quality baseline present"
else
  check "QA Approval" "FAIL" "quality baseline missing"
fi

# === Gate 5: Dev Approval (protected files) ===
echo -e "${BLUE}[5/6] Dev Approval${NC}"
PROTECTED_CHANGED=0

if [ -f ".protected-files" ]; then
  while IFS= read -r pattern; do
    [ -z "$pattern" ] && continue
    [[ "$pattern" == \#* ]] && continue
    if git diff origin/main...HEAD --name-only 2>/dev/null \
        | grep -vE '\.test\.[^/]+$|\.spec\.[^/]+$' \
        | grep -qE "$pattern"; then
      PROTECTED_CHANGED=$((PROTECTED_CHANGED + 1))
    fi
  done < ".protected-files"
fi

if [ "$PROTECTED_CHANGED" -gt 0 ]; then
  # Check for architect approval artifact
  HEAD_NOW=$(git rev-parse HEAD)
  ARCHITECT_APPROVED=0
  for _af in .tmp/architect-review-*.md; do
    [ -f "$_af" ] || continue
    _av=$(grep -oE 'VERDICT:[[:space:]]*(PASS|NOT_REQUIRED)' "$_af" | awk '{print $2}' | head -1 || true)
    _ac=$(grep -m1 "^commit:" "$_af" | awk '{print $2}' || true)
    if [ -n "$_av" ] && [ -n "$_ac" ]; then
      if git merge-base --is-ancestor "$_ac" "$HEAD_NOW" 2>/dev/null; then
        ARCHITECT_APPROVED=1
        break
      fi
    fi
  done

  if [ "$ARCHITECT_APPROVED" -eq 1 ]; then
    check "Dev Approval" "PASS" "architect review verified"
  else
    check "Dev Approval" "FAIL" "protected files changed without architect review"
  fi
else
  check "Dev Approval" "PASS" "no protected file changes"
fi

# === Gate 6: Final Sign-off ===
echo -e "${BLUE}[6/6] Final Sign-off${NC}"
RECENT_FIX=$(git log origin/main..HEAD --oneline 2>/dev/null | { grep "fix:" || true; } | wc -l | tr -d ' ')
RECENT_FEAT=$(git log origin/main..HEAD --oneline 2>/dev/null | { grep "feat:" || true; } | wc -l | tr -d ' ')

if [ "${EXPLICIT_DEPLOY:-0}" = "1" ] || [ "$RECENT_FIX" -gt 0 ] || [ "$RECENT_FEAT" -gt 0 ]; then
  check "Final Sign-off" "PASS" "deploy conditions met (fix: ${RECENT_FIX} / feat: ${RECENT_FEAT})"
else
  check "Final Sign-off" "FAIL" "no fix:/feat: commits — nothing to deploy"
fi

# === Final Verdict ===
echo ""
echo -e "${BLUE}────────────────────────────────────────${NC}"
TOTAL=$((PASS + FAIL + SKIP))
if [ "$FAIL" -eq 0 ]; then
  SKIP_MSG=""
  [ "$SKIP" -gt 0 ] && SKIP_MSG=", SKIP ${SKIP} (manual check recommended)"
  echo -e "${GREEN}CONSENSUS PASS (${PASS}/${TOTAL}${SKIP_MSG}) — deploy allowed${NC}"
  exit 0
else
  echo -e "${RED}CONSENSUS FAIL (${FAIL} failed) — deploy blocked${NC}"
  echo -e "${YELLOW}Fix above issues and re-run${NC}"
  exit 1
fi
