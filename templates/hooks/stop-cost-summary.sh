#!/usr/bin/env bash
# stop-cost-summary.sh — Aggregate session token usage at Stop time
#
# idea-factory v8 item 7.2 (docs/plans/v8-backlog.md Theme 7)
# Inspired by ECC's stop:cost-tracker pattern (docs/research/2026-04-12-ecc-comparison.md).
#
# ─────────────────────────────────────────────────────────────────────
# PURPOSE
# ─────────────────────────────────────────────────────────────────────
# At session Stop time, read the session transcript and sum tokens by
# category. Append one JSONL entry to .claude/audit/cost-YYYY-MM-DD.jsonl.
# CEO can `cat` that file to see the day's cost without reading transcripts.
#
# Token categories: input, output, cache_creation_input, cache_read_input.
# We deliberately do NOT compute dollar cost — model prices vary and
# change over time. Raw token counts are durable; conversion belongs to
# a separate report tool.
#
# ─────────────────────────────────────────────────────────────────────
# CRITICAL INVARIANT: THIS SCRIPT MUST ALWAYS EXIT 0
# ─────────────────────────────────────────────────────────────────────
# Same rule as check-audit.sh. Stop hooks must never block session
# completion. If transcript_path is missing, malformed, or empty:
# log zeros and continue. v7 regression guard (tests/invariant-exit-zero.sh)
# verifies this on every commit.

trap 'exit 0' ERR EXIT

{
  # ── Configuration ──────────────────────────────────────────────
  AUDIT_DIR="${CLAUDE_AUDIT_DIR:-.claude/audit}"
  mkdir -p "$AUDIT_DIR" 2>/dev/null || true

  # .gitignore protection (defense-in-depth, same pattern as check-audit.sh)
  # Cost logs may contain session ids which are not secrets but are also
  # not needed in version control.
  GITIGNORE_FILE="$AUDIT_DIR/.gitignore"
  if [ ! -f "$GITIGNORE_FILE" ] 2>/dev/null; then
    printf '*\n!.gitignore\n' > "$GITIGNORE_FILE" 2>/dev/null || true
  fi

  # Date helpers with fallbacks
  TODAY=$(date +%Y-%m-%d 2>/dev/null)
  [ -z "$TODAY" ] && TODAY="unknown-date"

  NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
  [ -z "$NOW" ] && NOW="unknown-time"

  COST_FILE="$AUDIT_DIR/cost-$TODAY.jsonl"

  # ── Read Stop hook payload from stdin ───────────────────────────
  PAYLOAD=""
  if [ ! -t 0 ]; then
    PAYLOAD=$(cat 2>/dev/null || echo '')
  fi
  [ -z "$PAYLOAD" ] && PAYLOAD='{}'

  # ── Extract session_id and transcript_path via python3 ─────────
  # Use python3 for JSON-aware parsing (handles escaped chars).
  # Pass payload via stdin pipe; never via shell-interpolated string.
  SESSION_ID="unknown"
  TRANSCRIPT_PATH=""
  if command -v python3 >/dev/null 2>&1; then
    EXTRACTED=$(printf '%s' "$PAYLOAD" | python3 -c "
import sys, json
try:
    d = json.loads(sys.stdin.read())
    sid = d.get('session_id', 'unknown') or 'unknown'
    tp = d.get('transcript_path', '') or ''
    if not isinstance(sid, str): sid = str(sid)
    if not isinstance(tp, str): tp = str(tp)
    print(sid)
    print(tp)
except Exception:
    print('unknown')
    print('')
" 2>/dev/null)
    SESSION_ID=$(printf '%s' "$EXTRACTED" | sed -n '1p')
    TRANSCRIPT_PATH=$(printf '%s' "$EXTRACTED" | sed -n '2p')
  fi
  [ -z "$SESSION_ID" ] && SESSION_ID="unknown"

  # ── Sum tokens from transcript JSONL if available ──────────────
  IN_T=0
  OUT_T=0
  CACHE_C=0
  CACHE_R=0

  if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ] && command -v python3 >/dev/null 2>&1; then
    # Pass path via env var (no shell interpolation = no injection risk).
    SUMS=$(TRANSCRIPT_PATH="$TRANSCRIPT_PATH" python3 -c "
import os, json
path = os.environ.get('TRANSCRIPT_PATH', '')
i = o = cc = cr = 0
try:
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                e = json.loads(line)
            except Exception:
                continue
            msg = e.get('message')
            if isinstance(msg, dict):
                u = msg.get('usage')
                if isinstance(u, dict):
                    i  += int(u.get('input_tokens', 0) or 0)
                    o  += int(u.get('output_tokens', 0) or 0)
                    cc += int(u.get('cache_creation_input_tokens', 0) or 0)
                    cr += int(u.get('cache_read_input_tokens', 0) or 0)
except Exception:
    pass
print(f'{i} {o} {cc} {cr}')
" 2>/dev/null)
    if [ -n "$SUMS" ]; then
      IN_T=$(printf '%s' "$SUMS" | awk '{print $1}')
      OUT_T=$(printf '%s' "$SUMS" | awk '{print $2}')
      CACHE_C=$(printf '%s' "$SUMS" | awk '{print $3}')
      CACHE_R=$(printf '%s' "$SUMS" | awk '{print $4}')
    fi
  fi
  # Defensive: ensure all values are numeric (default to 0 if not)
  case "$IN_T" in    ''|*[!0-9]*) IN_T=0 ;; esac
  case "$OUT_T" in   ''|*[!0-9]*) OUT_T=0 ;; esac
  case "$CACHE_C" in ''|*[!0-9]*) CACHE_C=0 ;; esac
  case "$CACHE_R" in ''|*[!0-9]*) CACHE_R=0 ;; esac

  # ── JSON-escape session_id (may contain unusual chars) ────────
  ESCAPED_SESSION=$(printf '%s' "$SESSION_ID" \
    | sed 's/\\/\\\\/g; s/"/\\"/g' 2>/dev/null \
    | tr -d '\n\r\t' 2>/dev/null)
  [ -z "$ESCAPED_SESSION" ] && ESCAPED_SESSION="unknown"

  # ── Compose JSONL entry ────────────────────────────────────────
  ENTRY=$(printf '{"ts":"%s","session":"%s","input_tokens":%s,"output_tokens":%s,"cache_creation_input_tokens":%s,"cache_read_input_tokens":%s}' \
    "$NOW" "$ESCAPED_SESSION" "$IN_T" "$OUT_T" "$CACHE_C" "$CACHE_R" 2>/dev/null)

  if [ -n "$ENTRY" ]; then
    printf '%s\n' "$ENTRY" >> "$COST_FILE" 2>/dev/null || true
  fi

} 2>/dev/null

# Always exit 0 — the most important line.
exit 0
