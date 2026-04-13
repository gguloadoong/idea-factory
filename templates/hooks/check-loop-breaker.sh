#!/usr/bin/env bash
# check-loop-breaker.sh — Fix-loop circuit breaker (PostToolUse Write|Edit)
#
# idea-factory v8 item 3.1 (docs/plans/v8-backlog.md Theme 3)
#
# ─────────────────────────────────────────────────────────────────────
# PURPOSE
# ─────────────────────────────────────────────────────────────────────
# Detect when Claude edits the same file repeatedly (3+ times in a
# short window), which signals a fix-loop: the same bug being retried
# with near-identical approaches. When detected, emit a warning via
# stdout that becomes a <system-reminder>.
#
# Detection logic:
#   - Track recent Write/Edit targets in a session-scoped ledger
#   - If the same file appears 3+ times in the last N entries → warn
#   - If 5+ times → escalate (stronger language)
#
# ─────────────────────────────────────────────────────────────────────
# CRITICAL INVARIANT: THIS SCRIPT MUST ALWAYS EXIT 0
# ─────────────────────────────────────────────────────────────────────

trap 'exit 0' ERR EXIT

{
  # ── Configuration ──────────────────────────────────────────────
  STATE_DIR="${CLAUDE_AUDIT_DIR:-.claude/audit}"
  WARN_THRESHOLD=${LOOP_WARN_THRESHOLD:-3}
  ESCALATE_THRESHOLD=${LOOP_ESCALATE_THRESHOLD:-5}
  WINDOW_SIZE=${LOOP_WINDOW_SIZE:-15}

  mkdir -p "$STATE_DIR" 2>/dev/null || true

  # .gitignore protection
  GITIGNORE_FILE="$STATE_DIR/.gitignore"
  if [ ! -f "$GITIGNORE_FILE" ] 2>/dev/null; then
    printf '*\n!.gitignore\n' > "$GITIGNORE_FILE" 2>/dev/null || true
  fi

  # ── Session-scoped ledger ──────────────────────────────────────
  SESSION_ID="${CLAUDE_SESSION_ID:-default}"
  SAFE_SESSION=$(printf '%s' "$SESSION_ID" | tr -cd 'a-zA-Z0-9_-' 2>/dev/null)
  [ -z "$SAFE_SESSION" ] && SAFE_SESSION="default"
  LEDGER_FILE="$STATE_DIR/.loop-ledger-${SAFE_SESSION}"

  # ── Read PostToolUse payload ───────────────────────────────────
  PAYLOAD=""
  if [ ! -t 0 ]; then
    PAYLOAD=$(cat 2>/dev/null || echo '')
  fi
  [ -z "$PAYLOAD" ] && PAYLOAD='{}'

  # ── Extract file_path via python3, grep fallback ───────────────
  FILE_PATH=""
  if command -v python3 >/dev/null 2>&1; then
    FILE_PATH=$(printf '%s' "$PAYLOAD" | python3 -c "
import sys, json
try:
    d = json.loads(sys.stdin.read())
    v = d.get('tool_input', {}).get('file_path', '')
    if not isinstance(v, str): v = ''
    sys.stdout.write(v)
except Exception:
    pass
" 2>/dev/null)
  fi
  if [ -z "$FILE_PATH" ]; then
    FILE_PATH=$(printf '%s' "$PAYLOAD" \
      | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' 2>/dev/null \
      | head -1 \
      | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/' 2>/dev/null)
  fi

  # Nothing to track if no file_path
  [ -z "$FILE_PATH" ] && exit 0

  # ── Append to ledger (rolling window) ──────────────────────────
  printf '%s\n' "$FILE_PATH" >> "$LEDGER_FILE" 2>/dev/null || true

  # Keep only last WINDOW_SIZE entries to prevent unbounded growth
  if [ -f "$LEDGER_FILE" ] 2>/dev/null; then
    LINE_COUNT=$(wc -l < "$LEDGER_FILE" 2>/dev/null | tr -d ' ')
    case "$LINE_COUNT" in
      ''|*[!0-9]*) LINE_COUNT=0 ;;
    esac
    if [ "$LINE_COUNT" -gt "$WINDOW_SIZE" ] 2>/dev/null; then
      tail -n "$WINDOW_SIZE" "$LEDGER_FILE" > "${LEDGER_FILE}.tmp" 2>/dev/null
      mv "${LEDGER_FILE}.tmp" "$LEDGER_FILE" 2>/dev/null || true
    fi
  fi

  # ── Count occurrences of current file in window ────────────────
  HIT_COUNT=0
  if [ -f "$LEDGER_FILE" ] 2>/dev/null; then
    HIT_COUNT=$(grep -cxF "$FILE_PATH" "$LEDGER_FILE" 2>/dev/null || echo 0)
    case "$HIT_COUNT" in
      ''|*[!0-9]*) HIT_COUNT=0 ;;
    esac
  fi

  # ── Emit warning if threshold reached ──────────────────────────
  if [ "$HIT_COUNT" -ge "$ESCALATE_THRESHOLD" ] 2>/dev/null; then
    # Extract just the filename for readability
    BASENAME=$(basename "$FILE_PATH" 2>/dev/null || echo "$FILE_PATH")
    cat <<EOF
[LOOP BREAKER — ESCALATE] ${BASENAME} 을 최근 ${HIT_COUNT}회 수정했습니다.

이것은 fix-loop 입니다. 같은 파일을 반복 수정하는 것은 근본 원인을 못 찾았다는 신호입니다.

즉시 중단하고 다음 중 하나를 실행하세요:
1. 이 파일 수정을 멈추고, 에러 메시지를 처음부터 다시 읽고, 완전히 다른 접근법을 시도
2. 문제의 근본 원인이 이 파일이 아닌 다른 곳에 있을 가능성을 조사
3. 사용자에게 escalate — 현재 상황과 시도한 접근법들을 설명

같은 접근법의 재시도는 금지입니다.
EOF

    # Log to audit
    NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "unknown")
    TODAY=$(date +%Y-%m-%d 2>/dev/null || echo "unknown-date")
    LOG_FILE="$STATE_DIR/loop-breaker-$TODAY.jsonl"
    # JSON-escape file path to prevent broken JSONL
    ESCAPED_PATH="$FILE_PATH"
    if command -v python3 >/dev/null 2>&1; then
      ESCAPED_PATH=$(python3 -c "import json,sys;print(json.dumps(sys.argv[1])[1:-1])" "$FILE_PATH" 2>/dev/null) || ESCAPED_PATH="$FILE_PATH"
    fi
    printf '{"ts":"%s","file":"%s","hits":%d,"level":"escalate"}\n' \
      "$NOW" "$ESCAPED_PATH" "$HIT_COUNT" >> "$LOG_FILE" 2>/dev/null || true

  elif [ "$HIT_COUNT" -ge "$WARN_THRESHOLD" ] 2>/dev/null; then
    BASENAME=$(basename "$FILE_PATH" 2>/dev/null || echo "$FILE_PATH")
    cat <<EOF
[LOOP BREAKER — WARNING] ${BASENAME} 을 최근 ${HIT_COUNT}회 수정했습니다.

반복 수정 패턴이 감지되었습니다. fix-loop에 빠지고 있을 수 있습니다.
다음을 점검하세요:
- 이전 수정이 왜 문제를 해결하지 못했는지 분석했는가?
- 같은 접근법을 반복하고 있지 않은가?
- 근본 원인이 다른 파일에 있을 가능성은?

3회 이상 같은 접근법 실패 시, 반드시 전략을 바꾸거나 escalate하세요.
EOF
  fi

} 2>/dev/null

exit 0
