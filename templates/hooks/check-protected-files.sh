#!/usr/bin/env bash
# check-protected-files.sh — Protected file change detector
#
# idea-factory v8 item 3.4 (docs/plans/v8-backlog.md Theme 3)
#
# ─────────────────────────────────────────────────────────────────────
# PURPOSE
# ─────────────────────────────────────────────────────────────────────
# PostToolUse Write|Edit hook. When Claude writes or edits a file,
# this hook checks whether it matches any glob pattern in
# protected-files.yml (or .protected-files.yml). On match, it:
#   1. Appends a JSONL audit entry to .claude/audit/protected-YYYY-MM-DD.jsonl
#   2. Emits a system-reminder warning to stderr
#
# ─────────────────────────────────────────────────────────────────────
# CRITICAL INVARIANT: THIS SCRIPT MUST ALWAYS EXIT 0
# ─────────────────────────────────────────────────────────────────────
# This is a LOGGING hook, not a blocking hook. Never exits non-zero.
#
# ─────────────────────────────────────────────────────────────────────
# DESIGN NOTE: PYTHON SCRIPT WRITTEN TO TEMPFILE
# ─────────────────────────────────────────────────────────────────────
# Writing the Python logic to a temp file avoids all shell quoting
# issues inside python3 -c '...'. Shell injection guard: file_path
# from payload is never interpolated into shell — only used as a
# Python string / filesystem path.

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

  LOG_FILE="$AUDIT_DIR/protected-$TODAY.jsonl"

  # ── Read PostToolUse payload from stdin ────────────────────────
  PAYLOAD=""
  if [ ! -t 0 ]; then
    PAYLOAD=$(cat 2>/dev/null || echo '')
  fi
  [ -z "$PAYLOAD" ] && PAYLOAD='{}'

  # ── Write Python script to a temp file ────────────────────────
  PY_SCRIPT=$(mktemp 2>/dev/null || mktemp -t chk_prot 2>/dev/null)
  [ -z "$PY_SCRIPT" ] && PY_SCRIPT="/tmp/check-protected-files-$$.py"

  cat > "$PY_SCRIPT" << 'PYEOF'
import os, sys, json, fnmatch, pathlib, re

NOW      = os.environ.get("NOW", "unknown-time")
LOG_FILE = os.environ.get("LOG_FILE", ".claude/audit/protected-unknown.jsonl")
CWD      = os.environ.get("HOOK_CWD", os.getcwd())

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

# ── Locate protected-files.yml ───────────────────────────────────
def find_protected_yml(start_dir):
    candidates = [
        ".protected-files.yml",
        "protected-files.yml",
        ".protected-files.yaml",
        "protected-files.yaml",
    ]
    cwd = pathlib.Path(start_dir).resolve()
    for _ in range(5):
        for name in candidates:
            p = cwd / name
            if p.is_file():
                return p
        parent = cwd.parent
        if parent == cwd:
            break
        cwd = parent
    return None

yml_path = find_protected_yml(CWD)
if yml_path is None:
    sys.exit(0)

# ── Parse YAML (stdlib only — no PyYAML dependency) ─────────────
def parse_protected_yml(path):
    rules = []
    current = None
    try:
        with open(path) as fh:
            lines = fh.readlines()
    except Exception:
        return rules
    for raw in lines:
        stripped = raw.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if stripped.startswith("- file:"):
            if current is not None:
                rules.append(current)
            val = stripped[len("- file:"):].strip().strip('"').strip("'")
            current = {"file": val, "reason": "", "trigger_on": "any_change", "reviewer": ""}
        elif current is not None:
            for key in ("reason", "trigger_on", "reviewer"):
                prefix = key + ":"
                if stripped.startswith(prefix):
                    val = stripped[len(prefix):].strip().strip('"').strip("'")
                    current[key] = val
                    break
    if current is not None:
        rules.append(current)
    return rules

rules = parse_protected_yml(yml_path)
if not rules:
    sys.exit(0)

# ── Glob matching ────────────────────────────────────────────────
def expand_braces(pattern):
    """Expand {a,b} into multiple patterns. Simple single-level."""
    m = re.search(r'\{([^}]+)\}', pattern)
    if not m:
        return [pattern]
    prefix = pattern[:m.start()]
    suffix = pattern[m.end():]
    results = []
    for alt in m.group(1).split(','):
        results.extend(expand_braces(prefix + alt + suffix))
    return results

def glob_match(filepath, pattern):
    """Match filepath against pattern supporting ** and {a,b}."""
    for expanded in expand_braces(pattern):
        # Convert ** to match any path segments
        # fnmatch doesn't support **, so convert to regex
        regex = expanded
        regex = regex.replace('.', r'\.')
        regex = regex.replace('**/', '(.+/)?')
        regex = regex.replace('**', '.*')
        regex = regex.replace('*', '[^/]*')
        regex = regex.replace('?', '[^/]')
        if re.search(regex, filepath) or re.search(regex, pathlib.PurePath(filepath).name):
            return True
    # Also try basic fnmatch
    try:
        if fnmatch.fnmatch(filepath, pattern) or fnmatch.fnmatch(pathlib.PurePath(filepath).name, pattern):
            return True
    except Exception:
        pass
    return False

fp = pathlib.PurePath(file_path)
fp_str = str(fp)

matched_rules = []
seen_patterns = set()
for rule in rules:
    pattern = rule.get("file", "")
    if not pattern or pattern in seen_patterns:
        continue
    if glob_match(fp_str, pattern):
        seen_patterns.add(pattern)
        matched_rules.append(rule)

if not matched_rules:
    sys.exit(0)

# ── Write audit entries ───────────────────────────────────────────
try:
    with open(LOG_FILE, "a") as lf:
        for rule in matched_rules:
            entry = {
                "ts":         NOW,
                "file":       file_path,
                "rule":       rule.get("file", ""),
                "reason":     rule.get("reason", ""),
                "reviewer":   rule.get("reviewer", ""),
                "trigger_on": rule.get("trigger_on", "any_change"),
                "severity":   "warning",
            }
            lf.write(json.dumps(entry, ensure_ascii=True) + "\n")
except Exception:
    pass

# ── Emit warnings to stdout (shell will redirect to stderr) ───────
for rule in matched_rules:
    reason   = rule.get("reason", "")
    reviewer = rule.get("reviewer", "")
    print("보호 파일 변경 감지: " + file_path + " — 사유: " + reason + " — 리뷰어: " + reviewer)
PYEOF

  # ── Run the Python script ──────────────────────────────────────
  WARNINGS=$(printf '%s' "$PAYLOAD" | \
    NOW="$NOW" LOG_FILE="$LOG_FILE" HOOK_CWD="$(pwd)" \
    python3 "$PY_SCRIPT" 2>/dev/null)

  # Clean up temp script
  rm -f "$PY_SCRIPT" 2>/dev/null || true

  # ── Emit warnings as system-reminder ──────────────────────────
  if [ -n "$WARNINGS" ]; then
    printf '\n<system-reminder>\n%s\n</system-reminder>\n' "$WARNINGS" >&2 2>/dev/null || true
  fi

} 2>/dev/null

# Always exit 0 — the most important line.
exit 0
