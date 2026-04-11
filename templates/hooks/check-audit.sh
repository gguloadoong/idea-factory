#!/usr/bin/env bash
# check-audit.sh — Exit-0 audit log for PreToolUse Bash matcher
#
# idea-factory v8 item 1.1 (docs/plans/v8-backlog.md Theme 1)
# First implementation of the "exit-0 advisory hook" future work that
# HARNESS-GUIDE.md v7.1 Runtime Safety section shelved.
#
# ─────────────────────────────────────────────────────────────────────
# PURPOSE
# ─────────────────────────────────────────────────────────────────────
# Log every Bash command Claude Code executes into
# .claude/audit/YYYY-MM-DD.jsonl for post-session review.
# Tag suspicious patterns with CAREFUL labels (deploy, redis-flush,
# npm-install, git-destructive, rm-rf) so an auditor can grep them.
#
# ─────────────────────────────────────────────────────────────────────
# CRITICAL INVARIANT: THIS SCRIPT MUST ALWAYS EXIT 0
# ─────────────────────────────────────────────────────────────────────
# v7 regression (2026-04) was caused by blocking PreToolUse hooks
# (check-careful.sh, check-safety.sh) that returned non-zero on risky
# commands, which Claude Code interpreted as "ask user to approve".
# Every Bash command in downstream projects then required manual
# approval, paralyzing autonomous loops. See:
#   docs/field-reports/2026-04-11-v7-propagation-postmortem.md
#
# This script complements the v7.1 deny-list (which catches strictly
# unrecoverable operations) by OBSERVING without HALTING. Any Bash
# command that would be blocked belongs in permissions.deny in
# settings.json, not here.
#
# The exit-0 guarantee is enforced by:
#   1. `trap 'exit 0' ERR EXIT` at the top
#   2. Every external command tolerates failure with `|| true` or
#      `2>/dev/null || ...`
#   3. Explicit `exit 0` at the bottom
#   4. Fallbacks for every value we extract (date, jq, grep, etc.)
#
# If you are editing this script and about to add `exit 1`, `return 1`,
# `set -e`, or anything that could cause non-zero exit: DO NOT.
# Wrap your new logic in `{ ... } 2>/dev/null || true` instead.

trap 'exit 0' ERR EXIT

{
  # ── Configuration ──────────────────────────────────────────────
  AUDIT_DIR="${CLAUDE_AUDIT_DIR:-.claude/audit}"
  MAX_CMD_LEN=2048

  # Create directory, silently tolerate failure
  mkdir -p "$AUDIT_DIR" 2>/dev/null || true

  # Date helpers with fallbacks
  TODAY=$(date +%Y-%m-%d 2>/dev/null)
  [ -z "$TODAY" ] && TODAY="unknown-date"

  NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
  [ -z "$NOW" ] && NOW="unknown-time"

  LOG_FILE="$AUDIT_DIR/$TODAY.jsonl"

  # ── Read hook payload from stdin ───────────────────────────────
  # Claude Code PreToolUse hooks receive a JSON payload on stdin
  # including tool_name, tool_input (Bash: .command), and metadata.
  # Parse defensively — never trust format.
  PAYLOAD=""
  if [ -p /dev/stdin ] || [ ! -t 0 ]; then
    PAYLOAD=$(cat 2>/dev/null || echo '')
  fi
  [ -z "$PAYLOAD" ] && PAYLOAD='{}'

  # Extract Bash command (best-effort grep; no jq dependency)
  # Matches: "command": "something" or "command":"something"
  CMD=$(printf '%s' "$PAYLOAD" \
    | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' 2>/dev/null \
    | head -1 \
    | sed 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/' 2>/dev/null)
  [ -z "$CMD" ] && CMD=""

  # Truncate extremely long commands
  CMD_LEN=${#CMD}
  if [ "$CMD_LEN" -gt "$MAX_CMD_LEN" ] 2>/dev/null; then
    CMD=$(printf '%s' "$CMD" | cut -c1-$MAX_CMD_LEN 2>/dev/null)
    CMD="${CMD}...[truncated]"
  fi

  # ── Pattern-based CAREFUL tagging (label only, NEVER block) ────
  TAGS=""
  if printf '%s' "$CMD" | grep -qE "vercel[[:space:]]+(--prod|env[[:space:]]+(add|rm))" 2>/dev/null; then
    TAGS="$TAGS deploy"
  fi
  if printf '%s' "$CMD" | grep -qE "redis-cli[[:space:]]+(FLUSHDB|FLUSHALL)" 2>/dev/null; then
    TAGS="$TAGS redis-flush"
  fi
  if printf '%s' "$CMD" | grep -qE "npm[[:space:]]+install[[:space:]]+[^-]" 2>/dev/null; then
    TAGS="$TAGS npm-install"
  fi
  if printf '%s' "$CMD" | grep -qE "git[[:space:]]+push.*--force|git[[:space:]]+reset.*--hard" 2>/dev/null; then
    TAGS="$TAGS git-destructive"
  fi
  if printf '%s' "$CMD" | grep -qE "rm[[:space:]]+-[a-zA-Z]*r[a-zA-Z]*f|rm[[:space:]]+-[a-zA-Z]*f[a-zA-Z]*r" 2>/dev/null; then
    TAGS="$TAGS rm-rf"
  fi
  # Trim leading space
  TAGS="${TAGS# }"

  # ── Session metadata ───────────────────────────────────────────
  SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"

  # ── Minimal JSON escape for the command string ────────────────
  # Escape: backslash → \\, double-quote → \", control chars → space
  ESCAPED_CMD=$(printf '%s' "$CMD" \
    | sed 's/\\/\\\\/g; s/"/\\"/g' 2>/dev/null \
    | tr -d '\n\r\t' 2>/dev/null)

  # ── Compose JSONL entry ────────────────────────────────────────
  ENTRY=$(printf '{"ts":"%s","session":"%s","matcher":"Bash","tags":"%s","cmd":"%s"}' \
    "$NOW" "$SESSION_ID" "$TAGS" "$ESCAPED_CMD" 2>/dev/null)

  # ── Append to log, silently tolerate all failures ──────────────
  if [ -n "$ENTRY" ]; then
    printf '%s\n' "$ENTRY" >> "$LOG_FILE" 2>/dev/null || true
  fi

} 2>/dev/null

# Explicit exit 0 — the most important line in this script.
exit 0
