#!/usr/bin/env bash
# create-pr.sh — 5-Stage PR Pipeline
# Generalized from market-dashboard-v5 (proven across 13 phases, 200+ PRs)
#
# Usage: bash scripts/create-pr.sh "PR title"
#
# Stages:
#   1/5  Build verification
#   2/5  code-reviewer artifact check (commit hash freshness)
#   3/5  Codex Gate (if CLI available)
#   4/5  PR creation with auto issue linking
#   5/5  Bot review polling (configurable timeout)
#
# Prerequisites:
#   - gh CLI authenticated
#   - code-reviewer artifact: .tmp/code-review-{BRANCH}.md
#   - (optional) codex CLI for cross-model review

set -euo pipefail

TITLE="${1:-}"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# --- Configuration (override via env) ---
BOT_POLL_TIMEOUT="${BOT_POLL_TIMEOUT:-600}"  # seconds (default 10min)
BOT_POLL_INTERVAL="${BOT_POLL_INTERVAL:-30}" # seconds
REPO="${GITHUB_REPO:-$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null || echo '')}"

if [ -z "$TITLE" ]; then
  echo -e "${RED}[pr] PR title required: bash scripts/create-pr.sh \"PR title\"${NC}"
  exit 1
fi

BRANCH=$(git rev-parse --abbrev-ref HEAD)
SAFE_BRANCH="${BRANCH//\//-}"

if [ "$BRANCH" = "main" ]; then
  echo -e "${RED}[pr] Cannot create PR from main branch.${NC}"
  exit 1
fi

# ========================================================================
# STAGE 1/5 — Build Verification
# ========================================================================
echo -e "${GREEN}[pr] === 1/5 Build Verification ===${NC}"
npm run build || { echo -e "${RED}[pr] Build failed${NC}"; exit 1; }

# --- 1.5/5 Architect Gate (protected files) ---
echo ""
echo -e "${GREEN}[pr] === 1.5/5 Architect Gate ===${NC}"

PROTECTED_FILES_CONFIG=".protected-files"
if [ -f "$PROTECTED_FILES_CONFIG" ]; then
  PROTECTED_PATTERN=$(grep -v '^#' "$PROTECTED_FILES_CONFIG" | grep -v '^$' | tr '\n' '|' | sed 's/|$//')

  if [ -n "$PROTECTED_PATTERN" ]; then
    MERGE_BASE=$(git merge-base origin/main HEAD 2>/dev/null) || {
      echo -e "${RED}[pr] Run: git fetch origin main${NC}"; exit 1;
    }
    # Exclude test/spec files from protected file detection
    PROTECTED_CHANGED=$(git diff "$MERGE_BASE" HEAD --name-only 2>/dev/null \
      | grep -E "$PROTECTED_PATTERN" \
      | grep -vE '\.(test|spec)\.(js|ts|jsx|tsx)$' || true)

    if [ -n "$PROTECTED_CHANGED" ]; then
      echo -e "${YELLOW}[pr] Protected file changes detected:${NC}"
      echo "$PROTECTED_CHANGED" | sed 's/^/    /'

      ARCHITECT_FILE=".tmp/architect-review-${SAFE_BRANCH}.md"
      if [ ! -f "$ARCHITECT_FILE" ]; then
        echo -e "${RED}[pr] Architect review artifact missing${NC}"
        echo -e "${YELLOW}[pr] Run: bash scripts/run-architect.sh${NC}"
        exit 1
      fi

      # Verify commit hash freshness
      ARCHITECT_COMMIT=$(grep -oE 'commit: [a-f0-9]+' "$ARCHITECT_FILE" | awk '{print $2}' | head -1 || echo "")
      HEAD_COMMIT_CHECK=$(git rev-parse HEAD)
      if [ "$ARCHITECT_COMMIT" != "$HEAD_COMMIT_CHECK" ]; then
        echo -e "${RED}[pr] Architect review stale (wrong commit)${NC}"
        echo -e "${YELLOW}[pr] Review: ${ARCHITECT_COMMIT:-none} / HEAD: ${HEAD_COMMIT_CHECK}${NC}"
        echo -e "${YELLOW}[pr] Re-run: bash scripts/run-architect.sh${NC}"
        exit 1
      fi

      # Check VERDICT (first line only to avoid false matches in body)
      if head -1 "$ARCHITECT_FILE" | grep -qiE 'VERDICT:[[:space:]]*BLOCK'; then
        echo -e "${RED}[pr] Architect VERDICT: BLOCK${NC}"
        exit 1
      fi

      ARCHITECT_VERDICT=$(head -1 "$ARCHITECT_FILE" | grep -oE 'VERDICT:[[:space:]]*(PASS|NOT_REQUIRED)')
      if [ -z "$ARCHITECT_VERDICT" ]; then
        echo -e "${RED}[pr] No valid VERDICT in architect artifact${NC}"
        exit 1
      fi
      echo -e "${GREEN}[pr] Architect ${ARCHITECT_VERDICT}${NC}"
    else
      echo -e "${GREEN}[pr] No protected file changes — architect gate skipped${NC}"
    fi
  fi
else
  echo -e "${GREEN}[pr] No .protected-files — architect gate skipped${NC}"
fi

# ========================================================================
# STAGE 2/5 — Code-Reviewer Artifact Check
# ========================================================================
echo ""
echo -e "${GREEN}[pr] === 2/5 Code-Reviewer Verification ===${NC}"

REVIEW_FILE=".tmp/code-review-${SAFE_BRANCH}.md"
if [ ! -f "$REVIEW_FILE" ]; then
  echo -e "${RED}[pr] Code-review artifact missing: ${REVIEW_FILE}${NC}"
  echo -e "${RED}[pr] Run code-reviewer first${NC}"
  exit 1
fi

REVIEW_COMMIT=$(grep -oE 'commit: [a-f0-9]+' "$REVIEW_FILE" | awk '{print $2}' || echo "")
HEAD_COMMIT=$(git rev-parse HEAD)

if [ "$REVIEW_COMMIT" != "$HEAD_COMMIT" ]; then
  echo -e "${RED}[pr] Code-review stale (commit mismatch)${NC}"
  echo -e "${YELLOW}[pr] Review: ${REVIEW_COMMIT:-none} / HEAD: ${HEAD_COMMIT}${NC}"
  exit 1
fi

if grep -qiE 'VERDICT:[[:space:]]*BLOCK' "$REVIEW_FILE"; then
  echo -e "${RED}[pr] Code-review VERDICT: BLOCK${NC}"
  exit 1
fi

CODE_REVIEWER_RESULT=$(grep -E '^\s*-?\s*\[(CRITICAL|HIGH|SEC|PERF|STYLE)\]' "$REVIEW_FILE" 2>/dev/null | head -10 || echo "No issues (PASS)")
echo -e "${GREEN}[pr] Code-review PASS (commit: ${HEAD_COMMIT:0:8})${NC}"

# ========================================================================
# STAGE 3/5 — Codex Gate (optional, skip if CLI not installed)
# ========================================================================
echo ""
echo -e "${GREEN}[pr] === 3/5 Codex Gate ===${NC}"
CODEX_STATUS="SKIPPED (codex CLI not installed)"

if command -v codex &>/dev/null; then
  set +e
  CODEX_OUTPUT=$(npm run review:gate < /dev/null 2>&1)
  CODEX_EXIT=$?
  set -e
  echo "$CODEX_OUTPUT"

  if [ "$CODEX_EXIT" -ne 0 ] || echo "$CODEX_OUTPUT" | grep -q "BLOCK"; then
    if [ "${SKIP_CODEX_REVIEW:-0}" = "1" ]; then
      echo -e "${YELLOW}[pr] Codex BLOCK overridden (SKIP_CODEX_REVIEW=1)${NC}"
      CODEX_STATUS="BLOCK -> overridden"
    else
      echo -e "${RED}[pr] Codex gate BLOCK${NC}"
      exit 1
    fi
  else
    CODEX_STATUS="PASS"
  fi
else
  echo -e "${YELLOW}[pr] Codex CLI not installed — skipped${NC}"
fi

# ========================================================================
# STAGE 4/5 — PR Creation with Auto Issue Linking
# ========================================================================
echo ""
echo -e "${GREEN}[pr] === 4/5 PR Creation ===${NC}"

# Extract issue number from branch name (feature/#36-description -> 36)
ISSUE_NUM=$(echo "$BRANCH" | grep -oE '#[0-9]+' | head -1 | tr -d '#')
CLOSES_LINE=""

if [ -n "$ISSUE_NUM" ]; then
  ISSUE_STATE=$(gh issue view "$ISSUE_NUM" --json state --jq '.state' 2>/dev/null || echo "NOT_FOUND")
  if [ "$ISSUE_STATE" = "OPEN" ]; then
    CLOSES_LINE="Closes #${ISSUE_NUM}"
    echo -e "${GREEN}[pr] Auto-linking issue #${ISSUE_NUM} (will close on merge)${NC}"
  elif [ "$ISSUE_STATE" = "CLOSED" ]; then
    CLOSES_LINE="Refs #${ISSUE_NUM}"
    echo -e "${YELLOW}[pr] Issue #${ISSUE_NUM} already closed — referencing only${NC}"
  else
    echo -e "${YELLOW}[pr] Issue #${ISSUE_NUM} not found — manual check needed${NC}"
  fi
else
  if echo "$TITLE" | grep -qiE '^(feat|fix):'; then
    echo -e "${RED}[pr] feat:/fix: PR requires issue number in branch name${NC}"
    echo -e "${RED}[pr] Branch format: feature/#ISSUE-description${NC}"
    exit 1
  fi
fi

REVIEW_BODY="## Independent Review Results

### code-reviewer (Claude Opus)
${CODE_REVIEWER_RESULT}

### Codex Gate
- ${CODEX_STATUS}

---
${CLOSES_LINE:+${CLOSES_LINE}

}---
Generated by Claude Code"

PR_URL=$(gh pr create --title "$TITLE" --body "$REVIEW_BODY" 2>&1 | grep "https://")
echo -e "${GREEN}[pr] PR created: $PR_URL${NC}"

PR_NUM=$(echo "$PR_URL" | grep -oE '[0-9]+$')

# --- 4.5/5 Project docs auto-update ---
echo ""
echo -e "${GREEN}[pr] === 4.5/5 Project Docs Update ===${NC}"
if [ -f "scripts/update-project-docs.sh" ]; then
  bash scripts/update-project-docs.sh 2>/dev/null || true
fi

# ========================================================================
# STAGE 5/5 — Bot Review Polling
# ========================================================================
echo ""
echo -e "${GREEN}[pr] === 5/5 Bot Review Polling (max ${BOT_POLL_TIMEOUT}s) ===${NC}"

if [ -z "$REPO" ]; then
  echo -e "${YELLOW}[pr] Cannot determine repo — skipping bot polling${NC}"
  echo -e "${GREEN}[pr] Done: $PR_URL${NC}"
  exit 0
fi

MAX_ITER=$((BOT_POLL_TIMEOUT / BOT_POLL_INTERVAL))
BOT_ARRIVED=0

for i in $(seq 1 "$MAX_ITER"); do
  sleep "$BOT_POLL_INTERVAL"
  ELAPSED=$((i * BOT_POLL_INTERVAL))

  # Check for any bot reviews
  REVIEW_COUNT=$(gh api "repos/${REPO}/pulls/${PR_NUM}/reviews" \
    --jq '[.[] | select(.user.type == "Bot")] | length' 2>/dev/null || echo "0")
  COMMENT_COUNT=$(gh api "repos/${REPO}/issues/${PR_NUM}/comments" \
    --jq '[.[] | select(.user.type == "Bot")] | length' 2>/dev/null || echo "0")

  TOTAL_BOT=$((REVIEW_COUNT + COMMENT_COUNT))
  echo "[pr] ${ELAPSED}s — bot reviews: ${REVIEW_COUNT}, bot comments: ${COMMENT_COUNT}"

  if [ "$TOTAL_BOT" -ge 2 ]; then
    echo -e "${GREEN}[pr] Bot review condition met!${NC}"
    BOT_ARRIVED=1
    break
  fi
done

if [ "$BOT_ARRIVED" -eq 0 ]; then
  echo -e "${YELLOW}[pr] Bot timeout — independent review results sufficient for merge${NC}"
fi

echo ""
echo -e "${GREEN}[pr] Done: $PR_URL${NC}"
echo -e "${YELLOW}[pr] Review bot feedback before merging${NC}"
