#!/usr/bin/env bash
# observability-push.sh — PostToolUse observability push to Discord / Telegram
#
# Resolves: idea-factory Issue #31 — Multi-Agent Observability
# Reference: github.com/disler/claude-code-hooks-multi-agent-observability
#
# ─────────────────────────────────────────────────────────────────────────────
# CRITICAL INVARIANT: THIS SCRIPT MUST ALWAYS EXIT 0 (v7.1 safety invariant)
# ─────────────────────────────────────────────────────────────────────────────
# Blocking hooks are architecturally incompatible with autonomous ralph loops.
# All errors — network, parsing, env — are silently swallowed. exit 0 is
# guaranteed by the trap at the top and the explicit exit 0 at the bottom.
#
# TRIGGER: PostToolUse (Task, Write, Edit, Bash — configurable via matcher)
#
# REQUIRED ENV:
#   OBSERVABILITY_WEBHOOK_URL  — Discord Incoming Webhook URL or Telegram API URL
#
# OPTIONAL ENV:
#   OBSERVABILITY_TYPE         — "discord" (default) | "telegram"
#   OBSERVABILITY_FILTER_LEVEL — "minimal" | "normal" (default) | "verbose"
#   OBSERVABILITY_DEBUG        — "1" → log payload to stderr only, no network call
# ─────────────────────────────────────────────────────────────────────────────

trap 'exit 0' ERR EXIT

{
  # ── Configuration ────────────────────────────────────────────────────────
  WEBHOOK_URL="${OBSERVABILITY_WEBHOOK_URL:-}"
  OBS_TYPE="${OBSERVABILITY_TYPE:-discord}"
  FILTER_LEVEL="${OBSERVABILITY_FILTER_LEVEL:-normal}"
  DEBUG_MODE="${OBSERVABILITY_DEBUG:-0}"
  CURL_TIMEOUT=5

  # ── Dry-run when OBSERVABILITY_WEBHOOK_URL is unset ─────────────────────
  DRY_RUN=0
  if [ -z "$WEBHOOK_URL" ]; then
    DRY_RUN=1
  fi

  # ── Read hook payload from stdin ────────────────────────────────────────
  # Claude Code PostToolUse hooks receive JSON on stdin:
  #   { "session_id": "...", "tool_name": "...", "tool_input": {...},
  #     "tool_response": {...} }
  PAYLOAD=""
  if [ -p /dev/stdin ] || [ ! -t 0 ]; then
    PAYLOAD=$(cat 2>/dev/null || echo '')
  fi
  [ -z "$PAYLOAD" ] && PAYLOAD='{}'

  # ── Extract fields with python3, fall back to empty strings ─────────────
  extract_field() {
    local field="$1"
    local default="${2:-}"
    if command -v python3 >/dev/null 2>&1; then
      python3 -c "
import sys, json
try:
    d = json.loads(sys.stdin.read())
    keys = '${field}'.split('.')
    v = d
    for k in keys:
        v = v.get(k, {}) if isinstance(v, dict) else {}
    if not isinstance(v, str):
        v = str(v) if v else '${default}'
    sys.stdout.write(v if v else '${default}')
except Exception:
    sys.stdout.write('${default}')
" 2>/dev/null <<< "$PAYLOAD"
    else
      echo "$default"
    fi
  }

  TOOL_NAME=$(extract_field "tool_name" "unknown")
  SESSION_ID=$(extract_field "session_id" "unknown")
  # Task tool: task description lives in tool_input.description
  TASK_DESC=$(extract_field "tool_input.description" "")
  # Bash tool: command
  BASH_CMD=$(extract_field "tool_input.command" "")
  # Agent name from env (Claude Code sets CLAUDE_AGENT_NAME in subagent contexts)
  AGENT_NAME="${CLAUDE_AGENT_NAME:-main}"
  # Story hint from env (ralph loops export CURRENT_STORY when available)
  CURRENT_STORY="${CURRENT_STORY:-}"

  # ── Filter level gating ──────────────────────────────────────────────────
  # minimal  → only Task tool events (agent spawns)
  # normal   → Task + Stop + session events
  # verbose  → everything (all PostToolUse)
  should_send=0
  case "$FILTER_LEVEL" in
    minimal)
      [ "$TOOL_NAME" = "Task" ] && should_send=1
      ;;
    normal)
      case "$TOOL_NAME" in
        Task|Stop|SessionStart) should_send=1 ;;
      esac
      ;;
    verbose)
      should_send=1
      ;;
  esac

  # Skip self (avoid potential loops from observability hook appearing in audit)
  if printf '%s' "$BASH_CMD" | grep -q "observability-push" 2>/dev/null; then
    should_send=0
  fi

  [ "$should_send" -eq 0 ] && exit 0

  # ── Secret masking ───────────────────────────────────────────────────────
  # Applies to all string values before inclusion in the webhook payload.
  # Patterns sourced from templates/observability/filter-rules.yaml.
  mask_secrets() {
    local text="$1"
    if command -v python3 >/dev/null 2>&1; then
      python3 -c "
import sys, re
text = sys.stdin.read()
patterns = [
    (r'AKIA[0-9A-Z]{16}',                        '[REDACTED-AWS-KEY]'),
    (r'sk-[A-Za-z0-9]{20,}',                      '[REDACTED-SK-KEY]'),
    (r'ghp_[A-Za-z0-9]{36}',                      '[REDACTED-GHP]'),
    (r'xoxb-[0-9]+-[A-Za-z0-9-]+',               '[REDACTED-SLACK]'),
    (r'AIza[0-9A-Za-z_-]{35}',                    '[REDACTED-GOOGLE]'),
    (r'Bearer\s+[A-Za-z0-9\-._~+/]{20,}',         '[REDACTED-BEARER]'),
    (r'[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}', '[REDACTED-EMAIL]'),
    (r'\\\$\{[A-Z_][A-Z0-9_]*\}',                 '[UNFILLED-PLACEHOLDER]'),
    (r'password[\"\'\\s:=]+[^\\s\"\']{4,}',       '[REDACTED-PASSWORD]'),
]
for pattern, replacement in patterns:
    try:
        text = re.sub(pattern, replacement, text, flags=re.IGNORECASE)
    except Exception:
        pass
sys.stdout.write(text)
" 2>/dev/null <<< "$text"
    else
      echo "$text"
    fi
  }

  TASK_DESC_SAFE=$(mask_secrets "$TASK_DESC")
  BASH_CMD_SAFE=$(mask_secrets "${BASH_CMD:0:200}")
  STORY_SAFE=$(mask_secrets "$CURRENT_STORY")

  # ── Build human-readable summary ─────────────────────────────────────────
  NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "unknown-time")
  SESSION_SHORT="${SESSION_ID:0:8}"

  SUMMARY="[${AGENT_NAME}] ${TOOL_NAME}"
  [ -n "$TASK_DESC_SAFE" ] && SUMMARY="$SUMMARY: ${TASK_DESC_SAFE:0:120}"
  [ -n "$BASH_CMD_SAFE" ]  && SUMMARY="$SUMMARY | cmd: ${BASH_CMD_SAFE}"
  [ -n "$STORY_SAFE" ]     && SUMMARY="$SUMMARY | story: ${STORY_SAFE:0:60}"

  # ── Build webhook payload ────────────────────────────────────────────────
  escape_json() {
    printf '%s' "$1" \
      | sed 's/\\/\\\\/g; s/"/\\"/g' 2>/dev/null \
      | tr -d '\n\r\t' 2>/dev/null
  }

  SUMMARY_ESC=$(escape_json "$SUMMARY")
  NOW_ESC=$(escape_json "$NOW")
  SESSION_ESC=$(escape_json "$SESSION_SHORT")
  AGENT_ESC=$(escape_json "$AGENT_NAME")
  TOOL_ESC=$(escape_json "$TOOL_NAME")
  LEVEL_ESC=$(escape_json "$FILTER_LEVEL")

  if [ "$OBS_TYPE" = "telegram" ]; then
    # Telegram sendMessage format (URL must be https://api.telegram.org/bot{TOKEN}/sendMessage?chat_id={ID})
    MESSAGE_TEXT="*[idea-factory observability]*\nagent: ${AGENT_NAME}\ntool: ${TOOL_NAME}\nsession: ${SESSION_SHORT}\ntime: ${NOW}\n\n${SUMMARY}"
    MSG_ESC=$(escape_json "$MESSAGE_TEXT")
    WEBHOOK_BODY="{\"text\":\"${MSG_ESC}\",\"parse_mode\":\"Markdown\"}"
  else
    # Discord Incoming Webhook format
    DISCORD_BODY=$(printf '{
  "username": "idea-factory-obs",
  "embeds": [{
    "title": "Agent Event",
    "color": 3447003,
    "fields": [
      {"name": "agent",   "value": "%s", "inline": true},
      {"name": "tool",    "value": "%s", "inline": true},
      {"name": "session", "value": "%s", "inline": true},
      {"name": "level",   "value": "%s", "inline": true},
      {"name": "summary", "value": "%s", "inline": false}
    ],
    "footer": {"text": "%s"}
  }]
}' "$AGENT_ESC" "$TOOL_ESC" "$SESSION_ESC" "$LEVEL_ESC" "$SUMMARY_ESC" "$NOW_ESC")
    WEBHOOK_BODY="$DISCORD_BODY"
  fi

  # ── Send or dry-run ──────────────────────────────────────────────────────
  if [ "$DEBUG_MODE" = "1" ]; then
    printf '[observability-push DEBUG] payload:\n%s\n' "$WEBHOOK_BODY" >&2
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[observability-push DRY-RUN] OBSERVABILITY_WEBHOOK_URL unset — skipping network call\n' >&2
    exit 0
  fi

  # Send with curl; 5-second timeout; all errors swallowed
  curl \
    --silent \
    --max-time "$CURL_TIMEOUT" \
    --request POST \
    --header "Content-Type: application/json" \
    --data "$WEBHOOK_BODY" \
    "$WEBHOOK_URL" \
    >/dev/null 2>&1 || true

} 2>/dev/null

# The most important line in this script.
exit 0
