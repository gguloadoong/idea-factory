#!/usr/bin/env bash
# scripts/lint-temporal-leakage.sh — Temporal leakage lint for time-series/trading code
#
# Usage: bash scripts/lint-temporal-leakage.sh [--path <dir>] [--lang python|javascript|typescript]
#
# Reads templates/lints/temporal-leakage/patterns.json and greps target files.
# Reports matches by severity. No --fix mode (auto-fix is unsafe for temporal bugs).
# Always exits 0 (advisory lint only).

set +e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PATTERNS_FILE="$ROOT/templates/lints/temporal-leakage/patterns.json"

# --- Defaults ---
SEARCH_PATH="."
LANG_FILTER=""

# --- Arg parsing ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --path)
      SEARCH_PATH="$2"
      shift 2
      ;;
    --lang)
      LANG_FILTER="$2"
      shift 2
      ;;
    --help|-h)
      echo "Usage: $0 [--path <dir>] [--lang python|javascript|typescript]"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 0
      ;;
  esac
done

# --- Validate patterns file ---
if [[ ! -f "$PATTERNS_FILE" ]]; then
  echo "ERROR: patterns file not found: $PATTERNS_FILE" >&2
  exit 0
fi

# Delegate all file collection, pattern matching, and output to Python.
# This avoids shell quoting/IFS issues with regex strings containing | and special chars.
python3 - "$PATTERNS_FILE" "$SEARCH_PATH" "$LANG_FILTER" <<'PYEOF'
import json
import os
import re
import sys

patterns_file = sys.argv[1]
search_path   = sys.argv[2]
lang_filter   = sys.argv[3] if len(sys.argv) > 3 else ""

# --- Load patterns ---
with open(patterns_file) as f:
    data = json.load(f)

# --- Extension -> language mapping ---
EXT_LANG = {"py": "python", "js": "javascript", "ts": "typescript"}
LANG_EXT  = {"python": ["py"], "javascript": ["js"], "typescript": ["ts"]}

def extensions_for_lang(lang):
    if lang:
        return LANG_EXT.get(lang, [])
    return ["py", "js", "ts"]

# --- Collect target files ---
abs_path = os.path.realpath(search_path)
if not os.path.isdir(abs_path):
    print(f"temporal-leakage-lint: no target files found in '{search_path}'")
    sys.exit(0)

exts = extensions_for_lang(lang_filter)
target_files = []
for dirpath, _, filenames in os.walk(abs_path):
    for fname in filenames:
        if any(fname.endswith("." + e) for e in exts):
            target_files.append(os.path.join(dirpath, fname))

if not target_files:
    print(f"temporal-leakage-lint: no target files found in '{search_path}'")
    sys.exit(0)

print(f"temporal-leakage-lint: scanning {len(target_files)} file(s) in '{search_path}'")
print()

# --- Run patterns ---
counts = {"HIGH": 0, "WARN": 0, "INFO": 0}
total = 0

for p in data.get("patterns", []):
    pid      = p.get("id", "")
    regex    = p.get("regex", "")
    severity = p.get("severity", "INFO")
    desc     = p.get("description", "")
    langs    = p.get("languages", [])

    # Skip if lang_filter set and pattern doesn't cover it
    if lang_filter and lang_filter not in langs:
        continue

    try:
        compiled = re.compile(regex)
    except re.error as e:
        print(f"[ERROR] pattern '{pid}' has invalid regex: {e}")
        continue

    for fpath in target_files:
        # Only scan files whose language matches the pattern's language list
        file_ext  = fpath.rsplit(".", 1)[-1] if "." in fpath else ""
        file_lang = EXT_LANG.get(file_ext, "")
        if file_lang not in langs:
            continue

        try:
            with open(fpath, encoding="utf-8", errors="replace") as fh:
                for lineno, line in enumerate(fh, 1):
                    if compiled.search(line):
                        print(f"[{severity}] {pid}")
                        print(f"  file: {fpath}")
                        print(f"  line {lineno}: {line.rstrip()}")
                        print(f"  desc: {desc}")
                        print()
                        counts[severity] = counts.get(severity, 0) + 1
                        total += 1
        except OSError:
            pass

print("--- temporal-leakage-lint summary ---")
print(f"  HIGH : {counts.get('HIGH', 0)}")
print(f"  WARN : {counts.get('WARN', 0)}")
print(f"  INFO : {counts.get('INFO', 0)}")
print(f"  total: {total} match(es)")
if total == 0:
    print("  OK: no temporal leakage patterns detected")

sys.exit(0)
PYEOF

exit 0
