#!/usr/bin/env bash
# create-pr.sh — 5-Stage PR Pipeline
# Ported from market-dashboard-v5 (proven across 13 phases, 200+ PRs)
#
# Usage: bash scripts/create-pr.sh "PR title"
#
# Stages:
#   1/5  Build verification + architect gate
#   2/5  code-reviewer artifact check (commit hash freshness)
#   3/5  Codex Gate (if CLI available) + 기각 항목 자동 Issue 등록
#   4/5  PR creation with auto issue linking
#   5/5  Bot review polling (Copilot 필수 + Gemini/CodeRabbit 중 1)
#
# Prerequisites:
#   - gh CLI authenticated
#   - code-reviewer artifact: .tmp/code-review-{BRANCH}.md
#   - (optional) codex CLI for cross-model review
#   - (optional) .protected-files for architect gate

set -euo pipefail

TITLE="${1:-}"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# --- Configuration (override via env) ---
BOT_POLL_TIMEOUT="${BOT_POLL_TIMEOUT:-900}"   # seconds (default 15min)
BOT_POLL_INTERVAL="${BOT_POLL_INTERVAL:-30}"  # seconds
REPO="${GITHUB_REPO:-$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null || echo '')}"

if [ -z "$TITLE" ]; then
  echo -e "${RED}[pr] PR 제목을 입력하세요: bash scripts/create-pr.sh \"PR 제목\"${NC}"
  exit 1
fi

BRANCH=$(git rev-parse --abbrev-ref HEAD)
# 브랜치명 / → - 치환 (artifact 경로 오류 방지, feature/xxx 대응)
SAFE_BRANCH="${BRANCH//\//-}"

if [ "$BRANCH" = "main" ]; then
  echo -e "${RED}[pr] main 브랜치에서는 PR을 생성할 수 없습니다.${NC}"
  exit 1
fi

# ========================================================================
# STAGE 1/5 — 빌드 확인
# ========================================================================
echo -e "${GREEN}[pr] === 1/5 빌드 확인 ===${NC}"
npm run build || { echo -e "${RED}[pr] 빌드 실패${NC}"; exit 1; }

# ─── 1.5/5 architect 게이트 — 보호 파일 변경 시 설계 리뷰 필수 ────────────
echo ""
echo -e "${GREEN}[pr] === 1.5/5 architect 게이트 ===${NC}"

# .protected-files 또는 .algo-files에서 패턴 동적 로드
PROTECTED_FILES_CONFIG=""
for candidate in ".protected-files" ".algo-files"; do
  if [ -f "$candidate" ]; then
    PROTECTED_FILES_CONFIG="$candidate"
    break
  fi
done

if [ -n "$PROTECTED_FILES_CONFIG" ]; then
  PROTECTED_PATTERN=$(grep -v '^#' "$PROTECTED_FILES_CONFIG" | grep -v '^$' | tr '\n' '|' | sed 's/|$//')

  # [HIGH FIX] merge-base 실패 시 명시적 오류 (silent pass 방지)
  MERGE_BASE=$(git merge-base origin/main HEAD 2>/dev/null) || {
    echo -e "${RED}[pr] origin/main fetch 필요: git fetch origin main${NC}"
    exit 1
  }
  # 테스트·스펙 파일 제외 — overkill 방지
  PROTECTED_FILES_CHANGED=$(git diff "$MERGE_BASE" HEAD --name-only 2>/dev/null \
    | grep -E "$PROTECTED_PATTERN" \
    | grep -vE '\.(test|spec)\.(js|ts|jsx|tsx)$' \
    || true)

  if [ -n "$PROTECTED_FILES_CHANGED" ]; then
    echo -e "${YELLOW}[pr] 보호 파일 변경 감지:${NC}"
    echo "$PROTECTED_FILES_CHANGED" | sed 's/^/    /'

    ARCHITECT_FILE=".tmp/architect-review-${SAFE_BRANCH}.md"

    if [ ! -f "$ARCHITECT_FILE" ]; then
      echo ""
      echo -e "${RED}[pr] ⛔ architect 리뷰 artifact 없음${NC}"
      echo -e "${RED}[pr]    보호 파일 변경 시 설계 리뷰 필수${NC}"
      echo -e "${YELLOW}[pr]    실행: npm run architect${NC}"
      exit 1
    fi

    # commit 일치 확인
    ARCHITECT_COMMIT=$(grep -oE 'commit: [a-f0-9]+' "$ARCHITECT_FILE" | awk '{print $2}' | head -1 || echo "")
    HEAD_COMMIT_CHECK=$(git rev-parse HEAD)
    if [ "$ARCHITECT_COMMIT" != "$HEAD_COMMIT_CHECK" ]; then
      echo -e "${RED}[pr] architect 리뷰가 현재 HEAD와 불일치${NC}"
      echo -e "${YELLOW}[pr]    리뷰 기준: ${ARCHITECT_COMMIT:-없음}${NC}"
      echo -e "${YELLOW}[pr]    현재 HEAD: ${HEAD_COMMIT_CHECK}${NC}"
      echo -e "${YELLOW}[pr]    재실행: npm run architect${NC}"
      exit 1
    fi

    # BLOCK 체크 — 첫 줄만 검사 (본문 내 BLOCK 언급 오탐 방지)
    if head -1 "$ARCHITECT_FILE" | grep -qiE 'VERDICT:[[:space:]]*BLOCK'; then
      echo -e "${RED}[pr] architect VERDICT: BLOCK — 설계 이슈 수정 후 재실행${NC}"
      exit 1
    fi

    # [CRITICAL FIX] fallback PASS 하드코딩 제거 — VERDICT 없으면 명시적 차단 (첫 줄만)
    ARCHITECT_VERDICT=$(head -1 "$ARCHITECT_FILE" | grep -oE 'VERDICT:[[:space:]]*(PASS|NOT_REQUIRED)')
    if [ -z "$ARCHITECT_VERDICT" ]; then
      echo -e "${RED}[pr] architect artifact에 유효한 VERDICT 없음 — npm run architect 재실행${NC}"
      exit 1
    fi
    echo -e "${GREEN}[pr] architect 리뷰 ${ARCHITECT_VERDICT} ✓${NC}"
  else
    echo -e "${GREEN}[pr] 보호 파일 변경 없음 — architect 게이트 스킵${NC}"
  fi
else
  echo -e "${YELLOW}[pr] .protected-files 없음 — architect 게이트 스킵${NC}"
fi

# ========================================================================
# STAGE 2/5 — code-reviewer artifact 검증
# ========================================================================
echo ""
echo -e "${GREEN}[pr] === 2/5 code-reviewer 검증 ===${NC}"

REVIEW_FILE=".tmp/code-review-${SAFE_BRANCH}.md"

if [ ! -f "$REVIEW_FILE" ]; then
  echo -e "${RED}[pr] code-review artifact 없음: ${REVIEW_FILE}${NC}"
  echo -e "${RED}[pr] 먼저 실행: npm run review:code${NC}"
  exit 1
fi

# 커밋 해시 최신성 검증
REVIEW_COMMIT=$(grep -oE 'commit: [a-f0-9]+' "$REVIEW_FILE" | awk '{print $2}' || echo "")
HEAD_COMMIT=$(git rev-parse HEAD)

if [ "$REVIEW_COMMIT" != "$HEAD_COMMIT" ]; then
  echo -e "${RED}[pr] code-review가 현재 HEAD와 불일치${NC}"
  echo -e "${YELLOW}[pr] 리뷰 기준 커밋: ${REVIEW_COMMIT:-없음}${NC}"
  echo -e "${YELLOW}[pr] 현재 HEAD:       ${HEAD_COMMIT}${NC}"
  echo -e "${RED}[pr] 재실행: npm run review:code${NC}"
  exit 1
fi

# BLOCK 재확인
if grep -qiE 'VERDICT:[[:space:]]*BLOCK' "$REVIEW_FILE"; then
  echo -e "${RED}[pr] code-review VERDICT: BLOCK — 수정 후 재실행 필요${NC}"
  exit 1
fi

# PR 본문용 추출
CODE_REVIEWER_RESULT=$(grep -E '^\s*-?\s*\[(CRITICAL|HIGH|SEC|PERF|STYLE)\]' "$REVIEW_FILE" 2>/dev/null | head -10 || echo "지적사항 없음 (PASS)")
echo -e "${GREEN}[pr] code-review PASS (커밋: ${HEAD_COMMIT:0:8})${NC}"
echo -e "${YELLOW}[pr] 주요 지적: ${CODE_REVIEWER_RESULT}${NC}"

# ========================================================================
# STAGE 3/5 — Codex Gate
# ========================================================================
echo ""
echo -e "${GREEN}[pr] === 3/5 Codex gate ===${NC}"
CODEX_STATUS="SKIPPED (codex CLI 미설치)"
CODEX_ISSUES_DECISION=""

if command -v codex &>/dev/null; then
  # Codex gate 실행 및 출력 캡처
  set +e
  CODEX_OUTPUT=$(npm run review:gate < /dev/null 2>&1)
  CODEX_EXIT=$?
  set -e
  echo "$CODEX_OUTPUT"

  # BLOCK 체크
  if [ "$CODEX_EXIT" -ne 0 ] || echo "$CODEX_OUTPUT" | grep -q "BLOCK"; then
    if [ "${SKIP_CODEX_REVIEW:-0}" = "1" ]; then
      echo -e "${YELLOW}[pr] Codex gate BLOCK → SKIP_CODEX_REVIEW=1 우회 (PR 본문에 사유 기록 필수)${NC}"
      CODEX_STATUS="BLOCK → SKIP_CODEX_REVIEW=1 우회"
    else
      echo -e "${YELLOW}[pr] Codex gate BLOCK — 수정 후 재실행하세요${NC}"
      exit 1
    fi
  fi

  # P1/P2/HIGH/CRITICAL 이슈 추출
  CODEX_ISSUES=$(echo "$CODEX_OUTPUT" | grep -E '^\s*-\s*\[P[12]\]|\[HIGH\]|\[CRITICAL\]' || true)

  if [ -n "$CODEX_ISSUES" ]; then
    echo ""
    echo -e "${RED}[pr] ══════════════════════════════════════════${NC}"
    echo -e "${RED}[pr] ⛔ Codex 지적사항 발견 — PR 생성 전 처리 결정 필수  ⛔${NC}"
    echo -e "${RED}[pr] ══════════════════════════════════════════${NC}"
    echo -e "${YELLOW}[pr] 발견된 지적사항:${NC}"
    echo "$CODEX_ISSUES"
    echo ""
    echo -e "${YELLOW}[pr] 각 항목에 대해 채택(수정 완료) 또는 기각(사유)을 입력하세요.${NC}"
    echo -e "${YELLOW}[pr] 예: [채택] xxx 수정 완료 / [기각] yyy — 현재 범위 밖, 백로그 등록${NC}"
    echo -e "${YELLOW}[pr] 빈 입력 시 PR 생성 중단됩니다.${NC}"
    echo -n "[pr] Codex 지적사항 처리 결과 입력: "
    read -r CODEX_ISSUES_DECISION

    if [ -z "$CODEX_ISSUES_DECISION" ]; then
      echo -e "${RED}[pr] 처리 결과 미입력 — PR 생성 중단${NC}"
      exit 1
    fi

    CODEX_STATUS="PASS (지적사항 처리: ${CODEX_ISSUES_DECISION})"

    # ── 기각 항목 자동 GitHub Issue 등록 ──────────────────────────────────
    if echo "$CODEX_ISSUES_DECISION" | grep -qiE '\[기각\]'; then
      echo ""
      echo -e "${YELLOW}[pr] 기각 항목 감지 — GitHub Issue 자동 등록 중...${NC}"

      REJECTION_ITEMS=$(echo "$CODEX_ISSUES_DECISION" | \
        grep -oE '\[기각\][^/\[]*' | \
        sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')

      while IFS= read -r REJECTION_ITEM; do
        [ -z "$REJECTION_ITEM" ] && continue

        ISSUE_LABEL="enhancement"
        if echo "$CODEX_ISSUES" | grep -qiE '\[P1\]|\[CRITICAL\]|\[HIGH\]'; then
          ISSUE_LABEL="bug"
        fi

        REJECTION_REASON=$(echo "$REJECTION_ITEM" | sed 's/\[기각\][[:space:]]*//' | sed 's/^[^—]*—[[:space:]]*//')
        REJECTION_DESC=$(echo "$REJECTION_ITEM" | sed 's/\[기각\][[:space:]]*//' | sed 's/[[:space:]]*—.*//')

        ISSUE_TITLE="[백로그] Codex 기각: ${REJECTION_DESC}"
        ISSUE_BODY="## Codex 지적 기각 항목 (자동 등록)

**원본 지적사항:**
${CODEX_ISSUES}

**기각된 항목:**
${REJECTION_ITEM}

**기각 사유:**
${REJECTION_REASON:-사유 미기입}

**연관 PR:** ${PR_URL:-PR 생성 전}
**기각 결정 전문:** ${CODEX_ISSUES_DECISION}

---
> 이 이슈는 create-pr.sh에 의해 자동 생성되었습니다. (기각 항목 백로그 누락 방지)
🤖 Generated by Claude Code"

        CREATED_ISSUE=$(gh issue create \
          --title "$ISSUE_TITLE" \
          --body "$ISSUE_BODY" \
          --label "ai-generated,${ISSUE_LABEL}" \
          2>/dev/null || echo "")

        if [ -n "$CREATED_ISSUE" ]; then
          echo -e "${GREEN}[pr] 기각 항목 Issue 등록: ${CREATED_ISSUE}${NC}"
        else
          echo -e "${YELLOW}[pr] Issue 등록 실패 — 수동 등록 필요: ${REJECTION_ITEM}${NC}"
        fi
      done <<< "$REJECTION_ITEMS"
    fi
  else
    if [[ "$CODEX_STATUS" != *"우회"* ]]; then
      CODEX_STATUS="PASS"
    fi
  fi
else
  echo -e "${YELLOW}[pr] Codex CLI 미설치 — 스킵${NC}"
fi

# ========================================================================
# STAGE 4/5 — PR 생성
# ========================================================================
echo ""
echo -e "${GREEN}[pr] === 4/5 PR 생성 ===${NC}"

# ── 이슈 자동 연결 ──────────────────────────────────────────────────────
ISSUE_NUM=$(echo "$BRANCH" | grep -oE '#[0-9]+' | head -1 | tr -d '#')
CLOSES_LINE=""

if [ -n "$ISSUE_NUM" ]; then
  ISSUE_STATE=$(gh issue view "$ISSUE_NUM" --json state --jq '.state' 2>/dev/null || echo "NOT_FOUND")
  if [ "$ISSUE_STATE" = "OPEN" ]; then
    CLOSES_LINE="Closes #${ISSUE_NUM}"
    echo -e "${GREEN}[pr] 이슈 #${ISSUE_NUM} 자동 연결 → PR 머지 시 자동 닫힘${NC}"
  elif [ "$ISSUE_STATE" = "CLOSED" ]; then
    CLOSES_LINE="Refs #${ISSUE_NUM}"
    echo -e "${YELLOW}[pr] 이슈 #${ISSUE_NUM} 이미 닫힘 → Refs로 참조${NC}"
  else
    echo -e "${YELLOW}[pr] 이슈 #${ISSUE_NUM} 조회 실패 → 수동 확인 필요${NC}"
  fi
else
  if echo "$TITLE" | grep -qiE '^(feat|fix):'; then
    echo -e "${RED}[pr] ⚠️ feat:/fix: PR인데 브랜치에 이슈번호 없음${NC}"
    echo -e "${RED}[pr]    브랜치 규칙: feature/#이슈번호-설명${NC}"
    echo -e "${YELLOW}[pr]    이슈 먼저 생성: gh issue create${NC}"
    exit 1
  fi
fi

REVIEW_BODY="## 독립 리뷰 결과

### code-reviewer (Claude Opus)
${CODE_REVIEWER_RESULT}

### Codex gate (OpenAI)
- ${CODEX_STATUS}

---
> ⚠️ PR 후 봇 리뷰 채택/기각 기준: 위 두 리뷰에서 이미 검토된 항목과 일치하면 채택, 상충하면 재검토 후 판단 (사전 승인 결과 원복 방지)

${CLOSES_LINE:+${CLOSES_LINE}

}---
🤖 Generated by Claude Code"

PR_URL=$(gh pr create --title "$TITLE" --body "$REVIEW_BODY" 2>&1 | grep "https://")

echo -e "${GREEN}[pr] PR 생성: $PR_URL${NC}"

PR_NUM=$(echo "$PR_URL" | grep -oE '[0-9]+$')

# ─── 4.5/5 프로젝트 문서 자동 현행화 ─────────────────────────────────────
echo ""
echo -e "${GREEN}[pr] === 4.5/5 프로젝트 문서 현행화 ===${NC}"
if [ -f "scripts/update-project-docs.sh" ]; then
  bash scripts/update-project-docs.sh 2>/dev/null || true
fi

# ========================================================================
# STAGE 5/5 — 봇 리뷰 폴링 (Copilot 필수 + Gemini/CodeRabbit 중 1)
# ========================================================================
echo ""
echo -e "${GREEN}[pr] === 5/5 봇 리뷰 폴링 (최대 ${BOT_POLL_TIMEOUT}s) ===${NC}"
echo -e "${YELLOW}[pr] 필수 조건: Copilot 도착 + Gemini·CodeRabbit 중 1명${NC}"
echo -e "${YELLOW}[pr] PR 전 검토 결과 참고: .tmp/code-review-${SAFE_BRANCH}.md${NC}"

if [ -z "$REPO" ]; then
  echo -e "${YELLOW}[pr] 레포 판별 불가 — 봇 폴링 스킵${NC}"
  echo -e "${GREEN}[pr] 완료: $PR_URL${NC}"
  exit 0
fi

MAX_ITER=$((BOT_POLL_TIMEOUT / BOT_POLL_INTERVAL))
COPILOT_ARRIVED=0
OTHER_ARRIVED=0

for i in $(seq 1 "$MAX_ITER"); do
  sleep "$BOT_POLL_INTERVAL"
  ELAPSED=$((i * BOT_POLL_INTERVAL))

  # Copilot — login: "copilot-pull-request-reviewer[bot]"
  COPILOT_COUNT=$(gh api "repos/${REPO}/pulls/${PR_NUM}/reviews" \
    --jq '[.[] | select(.user.login | test("copilot-pull-request-reviewer"; "i"))] | length' \
    2>/dev/null || echo "0")

  # Gemini (review)
  GEMINI_COUNT=$(gh api "repos/${REPO}/pulls/${PR_NUM}/reviews" \
    --jq '[.[] | select(.user.login | test("gemini"; "i"))] | length' \
    2>/dev/null || echo "0")

  # CodeRabbit (issue comment, "review in progress" 제외)
  CR_COUNT=$(gh api "repos/${REPO}/issues/${PR_NUM}/comments" \
    --jq '[.[] | select(.user.login | test("coderabbit"; "i")) | select(.body | contains("review in progress") | not)] | length' \
    2>/dev/null || echo "0")

  [ "$COPILOT_COUNT" -gt 0 ] && COPILOT_ARRIVED=1
  [ "$((GEMINI_COUNT + CR_COUNT))" -gt 0 ] && OTHER_ARRIVED=1

  echo "[pr] ${ELAPSED}s — Copilot:${COPILOT_ARRIVED} | Gemini:${GEMINI_COUNT} CodeRabbit:${CR_COUNT}"

  if [ "$COPILOT_ARRIVED" -eq 1 ] && [ "$OTHER_ARRIVED" -eq 1 ]; then
    echo -e "\n${GREEN}[pr] 필수 봇 리뷰 조건 충족!${NC}"
    break
  fi
done

# 타임아웃 처리
if [ "$COPILOT_ARRIVED" -eq 0 ] && [ "$OTHER_ARRIVED" -eq 0 ]; then
  echo -e "${YELLOW}[pr] 봇 미응답 — 독립 리뷰 결과만으로 머지 가능${NC}"
  gh pr comment "$PR_NUM" --body "봇 미응답 (타임아웃). 독립 리뷰 결과만으로 머지 가능." 2>/dev/null || true
elif [ "$COPILOT_ARRIVED" -eq 0 ]; then
  echo -e "${YELLOW}[pr] Copilot 미도착 — 수동 확인 필요${NC}"
  gh pr comment "$PR_NUM" --body "Copilot 리뷰 미도착. 머지 전 수동 확인 필요." 2>/dev/null || true
fi

# ── 봇 리뷰 상세 출력 ────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}[pr] ─── 봇 리뷰 상세 내용 ───${NC}"

gh api "repos/${REPO}/pulls/${PR_NUM}/reviews" --jq '.[] | "[\(.user.login)] \(.state)\n\(.body | .[0:400])\n---"' 2>/dev/null || true

gh api "repos/${REPO}/issues/${PR_NUM}/comments" \
  --jq '[.[] | select(.user.login | contains("coderabbit"))] | .[] | "[\(.user.login)]\n\(.body | .[0:600])\n---"' 2>/dev/null || true

INLINE_COUNT=$(gh api "repos/${REPO}/pulls/${PR_NUM}/comments" --jq 'length' 2>/dev/null || echo "0")
if [ "$INLINE_COUNT" -gt 0 ]; then
  echo ""
  echo -e "${YELLOW}[pr] 인라인 코멘트 ${INLINE_COUNT}건:${NC}"
  gh api "repos/${REPO}/pulls/${PR_NUM}/comments" \
    --jq '.[] | "[\(.user.login)] \(.path):\(.line // "?") — \(.body | .[0:200])\n---"' 2>/dev/null || true
fi

echo ""
echo -e "${RED}[pr] ══════════════════════════════════════════${NC}"
echo -e "${RED}[pr] ⚠️  봇 리뷰 응답 필수 — 지금 즉시 처리하세요  ⚠️${NC}"
echo -e "${RED}[pr] ══════════════════════════════════════════${NC}"
echo -e "${YELLOW}[pr] HIGH/CRITICAL → 코드 수정 후 push${NC}"
echo -e "${YELLOW}[pr] MEDIUM/LOW → 채택/기각 판단 후 PR 코멘트 작성${NC}"
echo -e "${YELLOW}[pr] 응답 없이 머지 금지 (CLAUDE.md 규칙)${NC}"
echo -e "${GREEN}[pr] PR: $PR_URL${NC}"
