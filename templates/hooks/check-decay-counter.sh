#!/usr/bin/env bash
# check-decay-counter.sh — Instruction decay counter + anti-quit reinjection
#
# idea-factory v8 item 4.1 (docs/plans/v8-backlog.md Theme 4)
#
# ─────────────────────────────────────────────────────────────────────
# PURPOSE
# ─────────────────────────────────────────────────────────────────────
# Count tool invocations per session. Every N invocations, reinject
# critical invariants as stdout (which Claude Code surfaces as
# <system-reminder>). This combats instruction compliance decay
# (Khare curve: 20-60% compliance after message 5-6).
#
# Reinjected rules:
#   - Anti-quit: never self-terminate work without user request
#   - Circuit breaker reminder: 3 identical failures → stop + escalate
#   - Session goal reminder (if .project/backlog.md exists)
#
# ─────────────────────────────────────────────────────────────────────
# CRITICAL INVARIANT: THIS SCRIPT MUST ALWAYS EXIT 0
# ─────────────────────────────────────────────────────────────────────

trap 'exit 0' ERR EXIT

{
  # ── Configuration ──────────────────────────────────────────────
  STATE_DIR="${CLAUDE_AUDIT_DIR:-.claude/audit}"
  REINJECT_EVERY=${DECAY_REINJECT_INTERVAL:-40}

  mkdir -p "$STATE_DIR" 2>/dev/null || true

  # .gitignore protection
  GITIGNORE_FILE="$STATE_DIR/.gitignore"
  if [ ! -f "$GITIGNORE_FILE" ] 2>/dev/null; then
    printf '*\n!.gitignore\n' > "$GITIGNORE_FILE" 2>/dev/null || true
  fi

  # ── Session-scoped counter file ────────────────────────────────
  SESSION_ID="${CLAUDE_SESSION_ID:-default}"
  # Sanitize session ID for filename safety
  SAFE_SESSION=$(printf '%s' "$SESSION_ID" | tr -cd 'a-zA-Z0-9_-' 2>/dev/null)
  [ -z "$SAFE_SESSION" ] && SAFE_SESSION="default"
  COUNTER_FILE="$STATE_DIR/.decay-counter-${SAFE_SESSION}"

  # ── Read and increment counter ─────────────────────────────────
  COUNT=0
  if [ -f "$COUNTER_FILE" ] 2>/dev/null; then
    COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)
    # Validate it's a number
    case "$COUNT" in
      ''|*[!0-9]*) COUNT=0 ;;
    esac
  fi
  COUNT=$((COUNT + 1))
  printf '%d' "$COUNT" > "$COUNTER_FILE" 2>/dev/null || true

  # ── Check if reinjection is due ────────────────────────────────
  REMAINDER=$((COUNT % REINJECT_EVERY))
  if [ "$REMAINDER" -ne 0 ] 2>/dev/null; then
    exit 0  # Not time yet
  fi

  # ── Build reinjection message ──────────────────────────────────
  # stdout from hooks becomes <system-reminder> content in Claude's context.
  # Use unquoted HEREDOC so $COUNT expands inline.

  GOAL_LINE=""
  if [ -f ".project/backlog.md" ] 2>/dev/null; then
    FIRST_ITEM=$(grep -m1 -E '^\s*-\s+' ".project/backlog.md" 2>/dev/null | head -1)
    if [ -n "$FIRST_ITEM" ]; then
      GOAL_LINE="Current top priority: $FIRST_ITEM"
    fi
  fi

  cat <<REINJECT
[INSTRUCTION REINJECTION — tool invocation #${COUNT}]

Critical rules (re-read carefully):

1. ANTI-QUIT: 사용자가 명시적으로 중단을 요청하기 전까지 자의적으로 작업을 중단하지 않는다. "오늘은 여기까지", "다음 세션에서 이어하자", "많이 진행했으니 쉬자" 등 금지. Claude에 피로·일일 한도는 없다. 작업이 남아있으면 계속한다.

2. CIRCUIT BREAKER: 같은 접근법으로 같은 문제를 3회 실패하면 즉시 멈추고 (a) 근본 원인을 분석하거나 (b) 완전히 다른 전략으로 전환하거나 (c) 사용자에게 escalate한다. 4회째 동일 시도는 금지.

3. CONTEXT HYGIENE: 실패한 시도의 세부사항이 컨텍스트를 오염시키고 있을 수 있다. 현재 접근법이 작동하지 않으면 한 발 물러나서 문제를 처음부터 재분석한다.
REINJECT

  # Append dynamic goal line if available
  if [ -n "$GOAL_LINE" ]; then
    printf '\n4. %s\n' "$GOAL_LINE"
  fi

} 2>/dev/null

exit 0
