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
#
# ─────────────────────────────────────────────────────────────────────
# DESIGN NOTE: ALL JSON HANDLING DONE IN A SINGLE python3 INVOCATION
# ─────────────────────────────────────────────────────────────────────
# Payload parsing, transcript reading, token summation, AND output JSON
# encoding all happen inside one python3 -c block. Rationale:
#   1. json.dumps guarantees valid JSONL even if session_id contains
#      control characters or unusual strings (Gemini review feedback).
#   2. Per-field safe_int catches non-numeric token values without
#      aborting the file loop (CodeRabbit review feedback).
#   3. Single structured call removes fragile multi-line stdout parsing
#      with sed (Copilot review feedback on newline-in-session_id).
#   4. Fewer shell/python boundary crossings = fewer places to break.

trap 'exit 0' ERR EXIT

{
  # ── Configuration ──────────────────────────────────────────────
  AUDIT_DIR="${CLAUDE_AUDIT_DIR:-.claude/audit}"
  mkdir -p "$AUDIT_DIR" 2>/dev/null || true

  # .gitignore protection (defense-in-depth, same pattern as check-audit.sh).
  GITIGNORE_FILE="$AUDIT_DIR/.gitignore"
  if [ ! -f "$GITIGNORE_FILE" ] 2>/dev/null; then
    printf '*\n!.gitignore\n' > "$GITIGNORE_FILE" 2>/dev/null || true
  fi

  # Date helpers with fallbacks.
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

  # ── Generate JSONL entry via a single python3 call ─────────────
  # Inputs:
  #   stdin:   PAYLOAD (Stop hook JSON)
  #   argv[1]: NOW (ISO 8601 UTC timestamp, shell-controlled, safe)
  # Output:
  #   One JSONL line on stdout (valid JSON, ready to append).
  # Defensive:
  #   - json.dumps handles any character safely (including control chars).
  #   - safe_int wraps per-field int() so a bad token value (string/float)
  #     is treated as 0 and does NOT abort the transcript scan.
  #   - All exceptions are caught; on total failure, a minimal entry with
  #     session=unknown and all tokens=0 is still emitted.
  ENTRY=$(printf '%s' "$PAYLOAD" | python3 -c '
import sys, json

NOW = sys.argv[1] if len(sys.argv) > 1 else "unknown-time"

def safe_int(v):
    """Coerce anything to int; return 0 on failure. Non-aborting."""
    try:
        return int(v)
    except Exception:
        return 0

# Parse Stop hook payload
try:
    payload = json.loads(sys.stdin.read())
    if not isinstance(payload, dict):
        payload = {}
except Exception:
    payload = {}

sid = payload.get("session_id") or "unknown"
if not isinstance(sid, str):
    sid = str(sid)

tp = payload.get("transcript_path") or ""
if not isinstance(tp, str):
    tp = ""

# Sum token categories from transcript JSONL (if available)
i = o = cc = cr = 0
if tp:
    try:
        with open(tp) as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    e = json.loads(line)
                except Exception:
                    continue
                if not isinstance(e, dict):
                    continue
                msg = e.get("message")
                if not isinstance(msg, dict):
                    continue
                u = msg.get("usage")
                if not isinstance(u, dict):
                    continue
                # Per-field safe_int prevents one bad value from aborting
                # the outer loop (CodeRabbit review feedback).
                i  += safe_int(u.get("input_tokens", 0))
                o  += safe_int(u.get("output_tokens", 0))
                cc += safe_int(u.get("cache_creation_input_tokens", 0))
                cr += safe_int(u.get("cache_read_input_tokens", 0))
    except Exception:
        pass

entry = {
    "ts": NOW,
    "session": sid,
    "input_tokens": i,
    "output_tokens": o,
    "cache_creation_input_tokens": cc,
    "cache_read_input_tokens": cr,
}
# json.dumps with ensure_ascii=True guarantees a single ASCII-safe line.
sys.stdout.write(json.dumps(entry, ensure_ascii=True))
' "$NOW" 2>/dev/null)

  # Append to cost log (silently tolerate write failures).
  if [ -n "$ENTRY" ]; then
    printf '%s\n' "$ENTRY" >> "$COST_FILE" 2>/dev/null || true
  fi

} 2>/dev/null

# Always exit 0 — the most important line.
exit 0
