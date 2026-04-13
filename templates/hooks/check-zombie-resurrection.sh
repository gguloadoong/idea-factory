#!/usr/bin/env bash
# check-zombie-resurrection.sh — Detect zombie resurrection of deleted code/symbols
#
# idea-factory v8 item 3.3 (docs/plans/v8-backlog.md Theme 3)
#
# ─────────────────────────────────────────────────────────────────────
# PURPOSE
# ─────────────────────────────────────────────────────────────────────
# When Claude writes or edits a file, check whether:
#   1. The file itself was previously deleted in git history (zombie file)
#   2. Symbols (function/variable names) added to the file were present
#      in a previously deleted version of that file
#
# Detects a real failure mode: agents re-introducing intentionally deleted
# code — instead of understanding why it was removed.
#
# ─────────────────────────────────────────────────────────────────────
# CRITICAL INVARIANT: THIS SCRIPT MUST ALWAYS EXIT 0
# ─────────────────────────────────────────────────────────────────────
# This is a LOGGING/WARNING hook, not a blocking hook.
# If git is unavailable or the repo check fails, exits silently.
#
# ─────────────────────────────────────────────────────────────────────
# DESIGN NOTE: ALL LOGIC IN A SINGLE python3 INVOCATION
# ─────────────────────────────────────────────────────────────────────
# Payload parsing, git inspection, symbol extraction, and JSON output
# all happen in one python3 -c block. Reduces shell/python boundary bugs.
# Shell injection guard: file_path from payload is NEVER interpolated
# into shell strings; passed via environment variable only.

trap 'exit 0' ERR EXIT

{
  # ── Configuration ──────────────────────────────────────────────
  AUDIT_DIR="${CLAUDE_AUDIT_DIR:-.claude/audit}"
  mkdir -p "$AUDIT_DIR" 2>/dev/null || true

  # .gitignore protection
  GITIGNORE_FILE="$AUDIT_DIR/.gitignore"
  if [ ! -f "$GITIGNORE_FILE" ] 2>/dev/null; then
    printf '*\n!.gitignore\n' > "$GITIGNORE_FILE" 2>/dev/null || true
  fi

  # Date helpers with fallbacks
  TODAY=$(date +%Y-%m-%d 2>/dev/null)
  [ -z "$TODAY" ] && TODAY="unknown-date"

  NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
  [ -z "$NOW" ] && NOW="unknown-time"

  LOG_FILE="$AUDIT_DIR/zombie-$TODAY.jsonl"

  # ── Read PostToolUse payload from stdin ────────────────────────
  PAYLOAD=""
  if [ ! -t 0 ]; then
    PAYLOAD=$(cat 2>/dev/null || echo '')
  fi
  [ -z "$PAYLOAD" ] && PAYLOAD='{}'

  # ── Check git availability (shell level, fast-path) ────────────
  if ! command -v git >/dev/null 2>&1; then
    exit 0
  fi

  # ── All processing in one python3 call ────────────────────────
  ENTRY=$(printf '%s' "$PAYLOAD" | NOW="$NOW" AUDIT_DIR="$AUDIT_DIR" python3 -c '
import os, sys, json, re, subprocess

NOW = os.environ.get("NOW", "unknown-time")

# ── Parse payload ────────────────────────────────────────────────
try:
    payload = json.loads(sys.stdin.read())
    if not isinstance(payload, dict):
        payload = {}
except Exception:
    payload = {}

tool_input = payload.get("tool_input") or {}
if not isinstance(tool_input, dict):
    sys.exit(0)

file_path = tool_input.get("file_path") or ""
if not isinstance(file_path, str) or not file_path:
    sys.exit(0)

# ── Verify git repo ──────────────────────────────────────────────
def run_git(args, cwd=None):
    """Run git command safely, return stdout or None on error."""
    try:
        result = subprocess.run(
            ["git"] + args,
            capture_output=True, text=True,
            timeout=10, cwd=cwd
        )
        if result.returncode == 0:
            return result.stdout
        return None
    except Exception:
        return None

# Determine repo root from file_path directory (or cwd fallback)
file_dir = os.path.dirname(os.path.abspath(file_path)) if file_path else None
if file_dir and not os.path.isdir(file_dir):
    file_dir = None

repo_root_out = run_git(["rev-parse", "--show-toplevel"], cwd=file_dir or ".")
if not repo_root_out:
    sys.exit(0)  # Not a git repo — silent exit
repo_root = os.path.realpath(repo_root_out.strip())

# ── Make file_path relative to repo root for git commands ────────
abs_file = os.path.realpath(os.path.abspath(file_path))
try:
    rel_file = os.path.relpath(abs_file, repo_root)
except ValueError:
    sys.exit(0)  # Different drives (Windows) — skip

# ── Check 1: Was this exact file deleted in git history? ─────────
zombie_file = False
deleted_log = run_git(
    ["log", "--diff-filter=D", "--name-only", "--pretty=format:", "--", rel_file],
    cwd=repo_root
)
if deleted_log and deleted_log.strip():
    # File appears in deletion history and currently exists on disk
    if os.path.isfile(abs_file):
        zombie_file = True

# ── Check 2: Symbol resurrection in file content ─────────────────
resurrected_symbols = []

# Extract symbols from past deletion diffs for this file
past_diff = run_git(
    ["log", "--diff-filter=D", "-p", "--", rel_file],
    cwd=repo_root
)

if past_diff:
    # Extract deleted lines (lines starting with "-" but not "---")
    deleted_symbols = set()
    for line in past_diff.splitlines():
        if line.startswith("-") and not line.startswith("---"):
            removed_line = line[1:]
            # Extract function/variable/class names (simple grep-level heuristic)
            # Matches: function foo, const foo, let foo, var foo, def foo,
            #          class Foo, export function foo, async function foo
            patterns = [
                r"\bfunction\s+(\w+)\s*\(",
                r"\bconst\s+(\w+)\s*[=\(]",
                r"\blet\s+(\w+)\s*[=;,]",
                r"\bvar\s+(\w+)\s*[=;,]",
                r"\bclass\s+(\w+)\b",
                r"\bdef\s+(\w+)\s*\(",
                r"\basync\s+function\s+(\w+)\s*\(",
                r"^(\w+)\s*[:=]\s*function",
                r"export\s+(?:default\s+)?function\s+(\w+)\s*\(",
            ]
            for pat in patterns:
                m = re.search(pat, removed_line)
                if m:
                    sym = m.group(1)
                    if len(sym) > 2:  # Skip trivially short names
                        deleted_symbols.add(sym)

    # Now check if current file content contains any of those symbols
    if deleted_symbols and os.path.isfile(abs_file):
        try:
            with open(abs_file, encoding="utf-8", errors="replace") as fh:
                current_content = fh.read()
            for sym in deleted_symbols:
                # Check for symbol presence (word boundary)
                if re.search(r"\b" + re.escape(sym) + r"\b", current_content):
                    resurrected_symbols.append(sym)
        except Exception:
            pass

# ── Emit entry if anything detected ──────────────────────────────
if not zombie_file and not resurrected_symbols:
    sys.exit(0)

severity = "high" if zombie_file else "warning"
note_parts = []
if zombie_file:
    note_parts.append(
        f"File '{rel_file}' was previously deleted in git history and has been recreated."
    )
if resurrected_symbols:
    note_parts.append(
        f"Symbols previously deleted from this file re-appeared: {resurrected_symbols}."
    )
note_parts.append(
    "Check CONTRACT.md for why this code was removed. "
    "If intentional, document justification in CONTRACT.md or decisions.md."
)

entry = {
    "ts": NOW,
    "file": file_path,
    "resurrected_symbols": resurrected_symbols,
    "zombie_file": zombie_file,
    "severity": severity,
    "note": " ".join(note_parts),
}
sys.stdout.write(json.dumps(entry, ensure_ascii=True))
' 2>/dev/null)

  # ── Write log + emit system-reminder warning ───────────────────
  if [ -n "$ENTRY" ]; then
    printf '%s\n' "$ENTRY" >> "$LOG_FILE" 2>/dev/null || true

    # Emit warning to stdout so Claude sees it as a system-reminder
    ZOMBIE_FILE=$(printf '%s' "$ENTRY" | python3 -c "
import json,sys
d=json.loads(sys.stdin.read())
print('yes' if d.get('zombie_file') else 'no')
" 2>/dev/null)
    SYMBOLS=$(printf '%s' "$ENTRY" | python3 -c "
import json,sys
d=json.loads(sys.stdin.read())
syms=d.get('resurrected_symbols',[])
print(', '.join(syms) if syms else '')
" 2>/dev/null)

    printf '\n<system-reminder>\n'
    printf '[ZOMBIE RESURRECTION DETECTED]\n'
    if [ "$ZOMBIE_FILE" = "yes" ]; then
      printf 'File was previously deleted in git history and has been recreated.\n'
    fi
    if [ -n "$SYMBOLS" ]; then
      printf 'Resurrected symbols: %s\n' "$SYMBOLS"
    fi
    printf 'Logged to: %s\n' "$LOG_FILE"
    printf 'ACTION REQUIRED: Check CONTRACT.md to understand why this code was removed.\n'
    printf 'If intentional, document justification in CONTRACT.md or decisions.md.\n'
    printf '</system-reminder>\n'
  fi

} 2>/dev/null

# Always exit 0 — the most important line.
exit 0
