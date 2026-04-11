#!/usr/bin/env bash
# check-config-protection.sh — Detect config file weakening
#
# idea-factory v8 item 7.3 (docs/plans/v8-backlog.md Theme 7)
# Inspired by ECC's pre:config-protection pattern.
#
# ─────────────────────────────────────────────────────────────────────
# PURPOSE
# ─────────────────────────────────────────────────────────────────────
# When Claude saves a config file (tsconfig, eslintrc, biome, jest,
# vitest, package.json, CI workflow), scan it for strictness-weakening
# patterns. If detected, log a warning to
# .claude/audit/config-guard-YYYY-MM-DD.jsonl.
#
# This catches a real failure mode: agents resolving type errors by
# flipping "strict": true → false, adding @ts-ignore, or disabling
# ESLint rules with "off" — instead of fixing the underlying code.
#
# ─────────────────────────────────────────────────────────────────────
# CRITICAL INVARIANT: THIS SCRIPT MUST ALWAYS EXIT 0
# ─────────────────────────────────────────────────────────────────────
# Same rule as every other idea-factory hook. This is a LOGGING hook,
# not a blocking hook. If the user wants to block, add the config file
# pattern to permissions.deny in settings.json instead.
#
# ─────────────────────────────────────────────────────────────────────
# DESIGN NOTE: ALL LOGIC IN A SINGLE python3 INVOCATION
# ─────────────────────────────────────────────────────────────────────
# Payload parsing, path filter, pattern detection, and JSON output all
# happen in one python3 -c block. Reduces shell/python boundary bugs
# (lesson from 7.2 PR review).

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

  LOG_FILE="$AUDIT_DIR/config-guard-$TODAY.jsonl"

  # ── Read PostToolUse payload from stdin ────────────────────────
  PAYLOAD=""
  if [ ! -t 0 ]; then
    PAYLOAD=$(cat 2>/dev/null || echo '')
  fi
  [ -z "$PAYLOAD" ] && PAYLOAD='{}'

  # ── All processing in one python3 call ────────────────────────
  # Inputs:
  #   stdin:   PAYLOAD (PostToolUse JSON)
  #   env:     NOW (ISO 8601 UTC, shell-controlled)
  # Output:
  #   Empty (nothing to log) OR one JSONL line (warning entry).
  #
  # Shell injection guard: file_path from payload is NEVER
  # interpolated into shell. It is opened via python's open() which
  # treats it as a literal filesystem path.
  ENTRY=$(printf '%s' "$PAYLOAD" | NOW="$NOW" python3 -c '
import os, sys, json, re, fnmatch

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

# ── Config file path filter ──────────────────────────────────────
# Match if path ends with a known config filename pattern.
CONFIG_GLOBS = [
    "*tsconfig*.json",
    "*.eslintrc",
    "*.eslintrc.*",
    "*eslint.config.js",
    "*eslint.config.mjs",
    "*eslint.config.cjs",
    "*eslint.config.ts",
    "*biome.json",
    "*biome.jsonc",
    "*jest.config.*",
    "*vitest.config.*",
    "*/package.json",
    "*/.github/workflows/*.yml",
    "*/.github/workflows/*.yaml",
    ".eslintrc",
    ".eslintrc.*",
    "package.json",
]

is_config = any(fnmatch.fnmatch(file_path, g) for g in CONFIG_GLOBS)
if not is_config:
    # Also check the bare basename (covers relative paths like "tsconfig.json")
    import os as _os
    basename = _os.path.basename(file_path)
    is_config = any(fnmatch.fnmatch(basename, g.lstrip("*/")) for g in CONFIG_GLOBS)

if not is_config:
    sys.exit(0)

# ── Read file content (fallback if unreadable) ───────────────────
try:
    with open(file_path) as fh:
        content = fh.read()
except Exception:
    sys.exit(0)

# ── Pattern battery ──────────────────────────────────────────────
# Each entry: (pattern_id, regex, explanation for humans)
PATTERNS = [
    ("strict_false",           r"\"strict\"\s*:\s*false"),
    ("noImplicitAny_false",    r"\"noImplicitAny\"\s*:\s*false"),
    ("skipLibCheck_true",      r"\"skipLibCheck\"\s*:\s*true"),
    ("strictNullChecks_false", r"\"strictNullChecks\"\s*:\s*false"),
    ("noImplicitReturns_false", r"\"noImplicitReturns\"\s*:\s*false"),
    ("allowJs_true",           r"\"allowJs\"\s*:\s*true"),
    ("ts_ignore_comment",      r"@ts-(ignore|nocheck)"),
    ("eslint_rule_off",        r":\s*\"off\""),
    ("passWithNoTests",        r"passWithNoTests"),
    ("coverage_disabled",      r"\"coverageThreshold\".*0\s*[,}]"),
]

found = []
for pid, pat in PATTERNS:
    if re.search(pat, content):
        found.append(pid)

if not found:
    sys.exit(0)  # No weakening detected, no log

# ── Emit JSONL entry ─────────────────────────────────────────────
entry = {
    "ts": NOW,
    "file": file_path,
    "weakening_patterns": found,
    "severity": "warning",
    "note": "Config weakening detected. Review whether this is intentional. "
            "If yes, document justification in CONTRACT.md or project decisions.md. "
            "If no, revert and fix the underlying code instead of relaxing the check.",
}
sys.stdout.write(json.dumps(entry, ensure_ascii=True))
' 2>/dev/null)

  # Append to log (silently tolerate failures)
  if [ -n "$ENTRY" ]; then
    printf '%s\n' "$ENTRY" >> "$LOG_FILE" 2>/dev/null || true
  fi

} 2>/dev/null

# Always exit 0 — the most important line.
exit 0
