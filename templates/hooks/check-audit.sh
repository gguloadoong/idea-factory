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

  # Ensure audit logs are NEVER committed — drop a local .gitignore on first run.
  # Defense-in-depth: even if the parent repo doesn't gitignore .claude/audit/,
  # this local .gitignore makes everything in this directory untracked.
  # Rationale: shell commands (and thus audit logs) can contain secrets in args.
  GITIGNORE_FILE="$AUDIT_DIR/.gitignore"
  if [ ! -f "$GITIGNORE_FILE" ] 2>/dev/null; then
    printf '*\n!.gitignore\n' > "$GITIGNORE_FILE" 2>/dev/null || true
  fi

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

  # Extract Bash command — prefer python3 (JSON-aware), grep as fallback.
  # python3 handles escaped quotes correctly; grep is a safety net only.
  CMD=""
  if command -v python3 >/dev/null 2>&1; then
    CMD=$(printf '%s' "$PAYLOAD" | python3 -c "
import sys, json
try:
    d = json.loads(sys.stdin.read())
    v = d.get('tool_input', {}).get('command', '')
    if not isinstance(v, str):
        v = str(v)
    sys.stdout.write(v)
except Exception:
    pass
" 2>/dev/null)
  fi
  # Fallback: grep-based extraction (may truncate on embedded escaped quotes)
  if [ -z "$CMD" ]; then
    CMD=$(printf '%s' "$PAYLOAD" \
      | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' 2>/dev/null \
      | head -1 \
      | sed 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/' 2>/dev/null)
  fi
  [ -z "$CMD" ] && CMD=""

  # Truncate extremely long commands
  CMD_LEN=${#CMD}
  if [ "$CMD_LEN" -gt "$MAX_CMD_LEN" ] 2>/dev/null; then
    CMD=$(printf '%s' "$CMD" | cut -c1-$MAX_CMD_LEN 2>/dev/null)
    CMD="${CMD}...[truncated]"
  fi

  # ── Pattern tagging (label only, NEVER block). Case-insensitive. ──
  # Tag values written to the `tags` field of the JSONL entry. Auditors
  # grep these labels — there is no literal "CAREFUL" prefix in the output.
  TAGS=""
  if printf '%s' "$CMD" | grep -qiE "vercel[[:space:]]+(--prod|env[[:space:]]+(add|rm))" 2>/dev/null; then
    TAGS="$TAGS deploy"
  fi
  if printf '%s' "$CMD" | grep -qiE "redis-cli[[:space:]]+(flushdb|flushall)" 2>/dev/null; then
    TAGS="$TAGS redis-flush"
  fi
  # npm install: matches "npm install", "npm install <pkg>", "npm install --flag",
  # and bare "npm install" at end of command.
  if printf '%s' "$CMD" | grep -qE "npm[[:space:]]+install([[:space:]]|$)" 2>/dev/null; then
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

  # ── Minimal JSON escape (applied to EVERY string field) ───────
  # Escape backslash and double-quote; strip \n \r \t so they don't
  # break the JSONL format. This MUST be applied to any field that
  # can contain user/env-controlled data (CMD, SESSION_ID, TAGS).
  escape_json() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' 2>/dev/null | tr -d '\n\r\t' 2>/dev/null
  }
  ESCAPED_CMD=$(escape_json "$CMD")
  ESCAPED_SESSION=$(escape_json "$SESSION_ID")
  ESCAPED_TAGS=$(escape_json "$TAGS")

  # ── Compose JSONL entry ────────────────────────────────────────
  # NOW is from `date -u +...` — format is controlled, no escape needed.
  ENTRY=$(printf '{"ts":"%s","session":"%s","matcher":"Bash","tags":"%s","cmd":"%s"}' \
    "$NOW" "$ESCAPED_SESSION" "$ESCAPED_TAGS" "$ESCAPED_CMD" 2>/dev/null)

  # ── Append to log, silently tolerate all failures ──────────────
  if [ -n "$ENTRY" ]; then
    printf '%s\n' "$ENTRY" >> "$LOG_FILE" 2>/dev/null || true
  fi

} 2>/dev/null

# Explicit exit 0 — the most important line in this script.
exit 0
