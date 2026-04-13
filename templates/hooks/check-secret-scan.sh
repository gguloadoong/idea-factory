#!/usr/bin/env bash
# check-secret-scan.sh — Write-time secret leakage scanner
#
# idea-factory v8 item 1.2 (docs/plans/v8-backlog.md Theme 1)
#
# ─────────────────────────────────────────────────────────────────────
# PURPOSE
# ─────────────────────────────────────────────────────────────────────
# When Claude saves a code file (Write or Edit), scan for patterns that
# indicate secret leakage in code:
#   - console.log calls that expose key/token/secret/password/api_key
#   - fetch calls with api_key= or token= query params
#   - throw new Error() exposing process.env values
#   - Hardcoded AWS keys (AKIA...), OpenAI keys (sk-...), GitHub tokens
#     (ghp_...), Slack tokens (xoxb-...)
#   - Hardcoded password literals
#
# Detected issues are logged to .claude/audit/secret-scan-YYYY-MM-DD.jsonl
# and surfaced as a system-reminder warning on stderr.
#
# Non-code files (.md, .txt, .json, .yaml, .toml, .lock, .gitignore,
# .env*, *.sh) are skipped.
#
# ─────────────────────────────────────────────────────────────────────
# CRITICAL INVARIANT: THIS SCRIPT MUST ALWAYS EXIT 0
# ─────────────────────────────────────────────────────────────────────
# This is a LOGGING/WARNING hook, not a blocking hook.
#
# REGISTRATION (opt-in — add manually to your project's .claude/settings.json):
#
#   "hooks": {
#     "PostToolUse": [
#       {
#         "matcher": "Write|Edit",
#         "hooks": [
#           {
#             "type": "command",
#             "command": "bash templates/hooks/check-secret-scan.sh",
#             "timeout": 5000
#           }
#         ]
#       }
#     ]
#   }
#
# ─────────────────────────────────────────────────────────────────────
# DESIGN: PYTHON SCRIPT WRITTEN TO TMPFILE (avoids shell quoting issues)
# ─────────────────────────────────────────────────────────────────────
# Payload parsing, file filtering, pattern detection, JSONL output all
# happen in a python3 script written to a temp file. This avoids the
# shell single-quote-in-python-string quoting problem that breaks -c blocks.
# Shell injection guard: file_path is NEVER interpolated into shell —
# it is passed via JSON payload and opened via python's open().

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

  LOG_FILE="$AUDIT_DIR/secret-scan-$TODAY.jsonl"

  # ── Read PostToolUse payload from stdin ────────────────────────
  PAYLOAD=""
  if [ ! -t 0 ]; then
    PAYLOAD=$(cat 2>/dev/null || echo '')
  fi
  [ -z "$PAYLOAD" ] && PAYLOAD='{}'

  # ── Write python scanner to a temp file ───────────────────────
  # Using a heredoc avoids all single-quote escaping issues.
  PY_SCRIPT=$(mktemp /tmp/secret-scan-XXXXXX.py 2>/dev/null || mktemp -t secret-scan 2>/dev/null)
  [ -z "$PY_SCRIPT" ] && PY_SCRIPT="/tmp/secret-scan-$$.py"

  cat > "$PY_SCRIPT" << 'PYEOF'
import os, sys, json, re

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
if not isinstance(file_path, str):
    file_path = ""

# ── Determine content to scan ────────────────────────────────────
# For Write hooks, prefer tool_input["content"] (already in payload).
# For Edit hooks, read the file from disk after the edit was applied.
content = tool_input.get("content") or tool_input.get("new_string") or ""
if not isinstance(content, str):
    content = ""

if not content and file_path:
    try:
        with open(file_path, encoding="utf-8", errors="replace") as fh:
            content = fh.read()
    except Exception:
        sys.exit(0)

if not content and not file_path:
    sys.exit(0)

# ── Non-code file filter ──────────────────────────────────────────
# Skip files that are not code (docs, configs, lock files, env files).
_basename = os.path.basename(file_path).lower() if file_path else ""
_ext = os.path.splitext(_basename)[1].lower() if "." in _basename else ""

NON_CODE_EXTS = {
    ".md", ".txt", ".rst", ".html", ".htm",
    ".json", ".jsonc", ".yaml", ".yml", ".toml",
    ".lock", ".ini", ".cfg", ".conf",
    ".gitignore", ".gitattributes", ".editorconfig",
    ".env", ".sh", ".bash", ".zsh",
    ".png", ".jpg", ".jpeg", ".gif", ".svg", ".ico",
    ".pdf", ".woff", ".woff2", ".ttf", ".eot",
}

NON_CODE_BASENAMES = {
    "package-lock.json", "yarn.lock", "pnpm-lock.yaml",
    "cargo.lock", "gemfile.lock",
    "license", "readme", "changelog", "authors", "notice",
    ".env", ".env.local", ".env.example",
}

_is_env_file = _basename.startswith(".env")
_is_non_code = (
    _ext in NON_CODE_EXTS
    or _basename in NON_CODE_BASENAMES
    or _is_env_file
)

if _is_non_code:
    sys.exit(0)

# ── Pattern battery ──────────────────────────────────────────────
# Format: (pattern_id, compiled_regex, severity)
# severity: HIGH = real key pattern; WARN = suspicious code pattern
PATTERNS = [
    # AWS key hardcoded
    ("aws_key",
     re.compile(r"AKIA[0-9A-Z]{16}", re.MULTILINE),
     "HIGH"),
    # OpenAI key hardcoded
    ("openai_key",
     re.compile(r"sk-[a-zA-Z0-9]{20,}", re.MULTILINE),
     "HIGH"),
    # GitHub personal access token
    ("github_token",
     re.compile(r"ghp_[a-zA-Z0-9]{36}", re.MULTILINE),
     "HIGH"),
    # Slack bot token
    ("slack_token",
     re.compile(r"xoxb-[a-zA-Z0-9\-]+", re.MULTILINE),
     "HIGH"),
    # Hardcoded password (non-empty literal) — uses double-quote delimiters
    # to avoid shell single-quote escaping issues
    ("hardcoded_password",
     re.compile(r"password\s*[:=]\s*[\"'][^\"']{1,}[\"']", re.IGNORECASE | re.MULTILINE),
     "HIGH"),
    # console.log leaking key/token/secret/password/api_key
    ("console_log_secret",
     re.compile(r"console\.log\s*\([^)]*(?:key|token|secret|password|api[_\-]?key)[^)]*\)", re.IGNORECASE | re.MULTILINE),
     "WARN"),
    # fetch with api_key= query param
    ("fetch_api_key",
     re.compile(r"fetch\s*\([^)]*api[_\-]?key\s*=", re.IGNORECASE | re.MULTILINE),
     "WARN"),
    # fetch with token= query param
    ("fetch_token",
     re.compile(r"fetch\s*\([^)]*[?&]token\s*=", re.IGNORECASE | re.MULTILINE),
     "WARN"),
    # throw new Error() exposing process.env
    ("throw_env",
     re.compile(r"throw\s+new\s+Error\s*\([^)]*process\.env", re.IGNORECASE | re.MULTILINE),
     "WARN"),
]

found_high = []
found_warn = []
for pid, pat, sev in PATTERNS:
    if pat.search(content):
        if sev == "HIGH":
            found_high.append(pid)
        else:
            found_warn.append(pid)

if not found_high and not found_warn:
    sys.exit(0)  # Clean — nothing to log

all_found = found_high + found_warn
severity = "HIGH" if found_high else "WARN"

entry = {
    "ts": NOW,
    "file": file_path if file_path else "<content-only>",
    "patterns_found": all_found,
    "severity": severity,
}
sys.stdout.write(json.dumps(entry, ensure_ascii=True))
PYEOF

  # ── Run the scanner ────────────────────────────────────────────
  ENTRY=$(printf '%s' "$PAYLOAD" | NOW="$NOW" python3 "$PY_SCRIPT" 2>/dev/null)
  rm -f "$PY_SCRIPT" 2>/dev/null || true

  # ── Append to log and emit warning ────────────────────────────
  if [ -n "$ENTRY" ]; then
    printf '%s\n' "$ENTRY" >> "$LOG_FILE" 2>/dev/null || true

    # Extract fields for the warning message
    SEVERITY=$(printf '%s' "$ENTRY" | python3 -c "
import json,sys
try:
    d=json.loads(sys.stdin.read())
    print(d.get('severity','?'))
except:
    print('?')
" 2>/dev/null)

    PATTERNS_LIST=$(printf '%s' "$ENTRY" | python3 -c "
import json,sys
try:
    d=json.loads(sys.stdin.read())
    print(', '.join(d.get('patterns_found',[])))
except:
    print('unknown')
" 2>/dev/null)

    FILE_FIELD=$(printf '%s' "$ENTRY" | python3 -c "
import json,sys
try:
    d=json.loads(sys.stdin.read())
    print(d.get('file','?'))
except:
    print('?')
" 2>/dev/null)

    # system-reminder style warning on stderr (Claude Code reads stderr as context)
    printf '\n<system-reminder>\n[secret-scan] %s detected in %s\nPatterns: %s\nLogged to: %s\nReview and remove secret leakage before committing.\n</system-reminder>\n' \
      "$SEVERITY" "$FILE_FIELD" "$PATTERNS_LIST" "$LOG_FILE" >&2 2>/dev/null || true
  fi

} 2>/dev/null

# Always exit 0 — the most important line.
exit 0
