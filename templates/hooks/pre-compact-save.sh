#!/usr/bin/env bash
# pre-compact-save.sh — Session state persistence at PreCompact time
#
# idea-factory v8 item 7.1 (docs/plans/v8-backlog.md Theme 7)
#
# ─────────────────────────────────────────────────────────────────────
# PURPOSE
# ─────────────────────────────────────────────────────────────────────
# At PreCompact time, save the current session state to
# .claude/state/session-YYYY-MM-DD-HH-MM.json so that after compaction
# (or after a context reset) the agent can restore phase context.
#
# Payload (from stdin): PreCompact hook JSON. Fields extracted:
#   session_id, trigger, summary — whatever is available.
#
# Output file: .claude/state/session-YYYY-MM-DD-HH-MM.json
# Format: {"ts":..., "session_id":..., "phase":..., "working_files":..., "summary":...}
#
# ─────────────────────────────────────────────────────────────────────
# CRITICAL INVARIANT: THIS SCRIPT MUST ALWAYS EXIT 0
# ─────────────────────────────────────────────────────────────────────
# Same rule as check-audit.sh. PreCompact hooks must never interfere
# with the compaction process. Any failure here is silent and safe.
#
# The exit-0 guarantee is enforced by:
#   1. `trap 'exit 0' ERR EXIT` at the top
#   2. Every external command tolerates failure with `|| true`
#   3. All logic wrapped in `{ ... } 2>/dev/null`
#   4. Explicit `exit 0` at the bottom

trap 'exit 0' ERR EXIT

{
  # ── Configuration ──────────────────────────────────────────────
  STATE_DIR="${CLAUDE_STATE_DIR:-.claude/state}"

  # Create state directory, silently tolerate failure
  mkdir -p "$STATE_DIR" 2>/dev/null || true

  # Auto-create .gitignore on first run so state files are never committed.
  # State files can contain project context that includes secrets or PII.
  GITIGNORE_FILE="$STATE_DIR/.gitignore"
  if [ ! -f "$GITIGNORE_FILE" ] 2>/dev/null; then
    printf '*\n!.gitignore\n' > "$GITIGNORE_FILE" 2>/dev/null || true
  fi

  # ── Timestamp helpers ──────────────────────────────────────────
  NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
  [ -z "$NOW" ] && NOW="unknown-time"

  FILE_TS=$(date +%Y-%m-%d-%H-%M 2>/dev/null)
  [ -z "$FILE_TS" ] && FILE_TS="unknown"

  STATE_FILE="$STATE_DIR/session-${FILE_TS}.json"

  # ── Read PreCompact hook payload from stdin ─────────────────────
  PAYLOAD=""
  if [ ! -t 0 ]; then
    PAYLOAD=$(cat 2>/dev/null || echo '')
  fi
  [ -z "$PAYLOAD" ] && PAYLOAD='{}'

  # ── Extract fields and write state via python3 ─────────────────
  # Use python3 so JSON encoding is always correct, matching the
  # stop-cost-summary.sh design (single python3 -c block pattern).
  # Inputs:
  #   stdin:   PAYLOAD (PreCompact hook JSON)
  #   argv[1]: NOW (ISO 8601 UTC timestamp)
  #   argv[2]: STATE_FILE path
  # Output: writes JSON file at STATE_FILE path
  printf '%s' "$PAYLOAD" | python3 -c '
import sys, json, os

NOW = sys.argv[1] if len(sys.argv) > 1 else "unknown-time"
STATE_FILE = sys.argv[2] if len(sys.argv) > 2 else ""

# Parse PreCompact payload
try:
    payload = json.loads(sys.stdin.read())
    if not isinstance(payload, dict):
        payload = {}
except Exception:
    payload = {}

# Extract fields defensively — only use what the payload provides
session_id = payload.get("session_id") or "unknown"
if not isinstance(session_id, str):
    session_id = str(session_id)

# summary: PreCompact payload may include a summary field
summary = payload.get("summary") or ""
if not isinstance(summary, str):
    summary = str(summary)

# phase: not in payload; detect from working files heuristic
# Look for idea-factory phase markers in common files
phase = "unknown"
try:
    for candidate in [".project/phase.txt", "PHASE", ".claude/phase.txt"]:
        if os.path.isfile(candidate):
            with open(candidate) as fh:
                val = fh.read().strip()
            if val:
                phase = val[:64]
            break
except Exception:
    pass

# working_files: files modified in the last 30 minutes (git-based, best-effort)
working_files = []
try:
    import subprocess
    result = subprocess.run(
        ["git", "diff", "--name-only", "HEAD"],
        capture_output=True, text=True, timeout=5
    )
    if result.returncode == 0:
        working_files = [f for f in result.stdout.splitlines() if f.strip()][:20]
except Exception:
    pass

state = {
    "ts": NOW,
    "session_id": session_id,
    "phase": phase,
    "working_files": working_files,
    "summary": summary,
}

if not STATE_FILE:
    sys.exit(0)

try:
    with open(STATE_FILE, "w") as fh:
        json.dump(state, fh, ensure_ascii=True, indent=2)
        fh.write("\n")
except Exception:
    pass
' "$NOW" "$STATE_FILE" 2>/dev/null || true

} 2>/dev/null

# Explicit exit 0 — the most important line in this script.
exit 0
