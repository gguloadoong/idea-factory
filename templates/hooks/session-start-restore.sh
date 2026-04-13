#!/usr/bin/env bash
# session-start-restore.sh — Session state restore hint at SessionStart time
#
# idea-factory v8 item 7.1 (docs/plans/v8-backlog.md Theme 7)
#
# ─────────────────────────────────────────────────────────────────────
# PURPOSE
# ─────────────────────────────────────────────────────────────────────
# At SessionStart time, look for the most recent session state file
# saved by pre-compact-save.sh. If a recent (< 24 h) file exists,
# emit a system-reminder on stdout so Claude knows context is available.
#
# Output (stdout): system-reminder line if recent state found, else silent.
# The Claude Code runtime injects stdout of SessionStart hooks as
# <system-reminder> content into the first turn.
#
# Stale guard: files older than 24 hours are ignored — they describe
# a session too far in the past to be useful context.
#
# ─────────────────────────────────────────────────────────────────────
# CRITICAL INVARIANT: THIS SCRIPT MUST ALWAYS EXIT 0
# ─────────────────────────────────────────────────────────────────────
# SessionStart hooks must never prevent a session from starting.
# Any failure here is silent. Same guarantee pattern as check-audit.sh.

trap 'exit 0' ERR EXIT

{
  # ── Configuration ──────────────────────────────────────────────
  STATE_DIR="${CLAUDE_STATE_DIR:-.claude/state}"
  MAX_AGE_SECONDS=86400  # 24 hours

  # If state directory doesn't exist, nothing to do
  [ -d "$STATE_DIR" ] 2>/dev/null || exit 0

  # ── Find the most recent session state file ─────────────────────
  # Use python3 for portability — stat -c (GNU) vs stat -f (BSD) differ.
  # python3 os.path.getmtime is cross-platform.
  printf '' | python3 -c '
import sys, os, json, glob

STATE_DIR = os.environ.get("CLAUDE_STATE_DIR", ".claude/state")
MAX_AGE = int(sys.argv[1]) if len(sys.argv) > 1 else 86400

import time
now = time.time()

# Find all session state files
pattern = os.path.join(STATE_DIR, "session-*.json")
candidates = glob.glob(pattern)
if not candidates:
    sys.exit(0)

# Sort by mtime descending, pick the newest
try:
    candidates.sort(key=lambda f: os.path.getmtime(f), reverse=True)
except Exception:
    sys.exit(0)

newest = candidates[0]

# Check age
try:
    age = now - os.path.getmtime(newest)
except Exception:
    sys.exit(0)

if age > MAX_AGE:
    # Stale — do not emit
    sys.exit(0)

# Parse the state file for a helpful summary
session_id = "unknown"
phase = "unknown"
summary = ""
working_files = []
ts = ""

try:
    with open(newest) as fh:
        state = json.load(fh)
    if isinstance(state, dict):
        session_id = state.get("session_id") or "unknown"
        phase = state.get("phase") or "unknown"
        summary = state.get("summary") or ""
        working_files = state.get("working_files") or []
        ts = state.get("ts") or ""
except Exception:
    pass

# Emit a system-reminder hint
parts = [f"이전 세션 상태 발견: {newest}"]
if ts:
    parts.append(f"저장 시각: {ts}")
if phase and phase != "unknown":
    parts.append(f"phase: {phase}")
if working_files:
    files_str = ", ".join(working_files[:5])
    if len(working_files) > 5:
        files_str += f" 외 {len(working_files) - 5}개"
    parts.append(f"작업 파일: {files_str}")
if summary:
    # Truncate long summaries
    short = summary[:120] + ("..." if len(summary) > 120 else "")
    parts.append(f"요약: {short}")

parts.append("필요하면 해당 파일을 읽어서 컨텍스트를 복원하세요.")

print(" | ".join(parts))
' "$MAX_AGE_SECONDS" 2>/dev/null || true

} 2>/dev/null

# Explicit exit 0 — the most important line in this script.
exit 0
