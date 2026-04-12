#!/usr/bin/env bash
# stop-learning-capture.sh — Session-end learning capture prompt
#
# idea-factory v8 item 2.4 (docs/plans/v8-backlog.md Theme 2)
#
# ─────────────────────────────────────────────────────────────────────
# PURPOSE
# ─────────────────────────────────────────────────────────────────────
# At session Stop, check if this session produced learnings worth
# recording. If the learning layer exists (docs/research/ or
# docs/field-reports/), emit a reminder via stdout so Claude considers
# capturing insights before the session context is lost.
#
# Detection heuristic (lightweight, avoids false positives):
#   - Learning layer dirs must exist (only idea-factory scaffolded projects)
#   - Session must have substantial activity (20+ audit log entries)
#   - OR new decisions were made (.project/decisions.md modified)
#   - OR bugs were fixed (git diff has "fix:" in recent commits)
#
# ─────────────────────────────────────────────────────────────────────
# CRITICAL INVARIANT: THIS SCRIPT MUST ALWAYS EXIT 0
# ─────────────────────────────────────────────────────────────────────

trap 'exit 0' ERR EXIT

{
  # ── Check if learning layer exists ─────────────────────────────
  # Only fire in projects scaffolded with idea-factory's learning layer.
  # If neither dir exists, this is not an idea-factory project → skip.
  HAS_RESEARCH=false
  HAS_FIELD=false
  [ -d "docs/research" ] 2>/dev/null && HAS_RESEARCH=true
  [ -d "docs/field-reports" ] 2>/dev/null && HAS_FIELD=true

  if [ "$HAS_RESEARCH" = false ] && [ "$HAS_FIELD" = false ]; then
    exit 0  # Not an idea-factory project with learning layer
  fi

  # ── Heuristic: was this session substantial? ───────────────────
  AUDIT_DIR="${CLAUDE_AUDIT_DIR:-.claude/audit}"
  TODAY=$(date +%Y-%m-%d 2>/dev/null || echo "unknown")
  AUDIT_FILE="$AUDIT_DIR/$TODAY.jsonl"
  SHOULD_PROMPT=false

  # Check 1: 20+ audit entries today = substantial session
  if [ -f "$AUDIT_FILE" ] 2>/dev/null; then
    ENTRY_COUNT=$(wc -l < "$AUDIT_FILE" 2>/dev/null | tr -d ' ')
    case "$ENTRY_COUNT" in
      ''|*[!0-9]*) ENTRY_COUNT=0 ;;
    esac
    if [ "$ENTRY_COUNT" -ge 20 ] 2>/dev/null; then
      SHOULD_PROMPT=true
    fi
  fi

  # Check 2: decisions.md was modified in this session
  if [ "$SHOULD_PROMPT" = false ] && [ -f ".project/decisions.md" ] 2>/dev/null; then
    if git diff --name-only HEAD~1 HEAD 2>/dev/null | grep -qxF "decisions.md" 2>/dev/null; then
      SHOULD_PROMPT=true
    fi
  fi

  # Check 3: recent commits have fix: or feat: (new work done)
  if [ "$SHOULD_PROMPT" = false ]; then
    RECENT=$(git log --oneline -5 --since="8 hours ago" --no-merges 2>/dev/null || echo "")
    if printf '%s' "$RECENT" | grep -qE "^[a-f0-9]+ (fix|feat):" 2>/dev/null; then
      SHOULD_PROMPT=true
    fi
  fi

  if [ "$SHOULD_PROMPT" = false ]; then
    exit 0  # Session too small or no significant work detected
  fi

  # ── Emit learning capture prompt ───────────────────────────────
  cat <<'CAPTURE'
[SESSION LEARNING CAPTURE]

이번 세션에서 기록할 만한 학습이 있는지 점검하세요:

1. **새로운 gap 발견**: 하려고 했는데 안 된 것, 있어야 하는데 없는 것
   → docs/plans/v8-backlog.md 에 항목 추가

2. **리서치 결과**: 외부 조사, 에이전트 심층 분석, 비교 연구
   → docs/research/YYYY-MM-DD-주제.md 로 저장

3. **실전 교훈**: 회귀, 실패 원인, 예상 밖 동작, postmortem
   → docs/field-reports/YYYY-MM-DD-주제.md 로 저장

4. **결정 사항**: 설계 분기점에서 내린 판단과 근거
   → .project/decisions.md 에 추가

기록할 것이 없으면 무시해도 됩니다.
CAPTURE

} 2>/dev/null

exit 0
