#!/usr/bin/env bash
# check-copy-drift.sh — Detect drift between local copied files and upstream
#
# idea-factory v8 item 5.4 (docs/plans/v8-backlog.md Theme 5)
#
# ─────────────────────────────────────────────────────────────────────
# PURPOSE
# ─────────────────────────────────────────────────────────────────────
# Reads COPIED-FROM.md in the project root, finds all registered copy
# entries, fetches the current upstream content via `gh api`, diffs
# against local files, and reports drift.
#
# USAGE
#   check-copy-drift.sh [--check] [--verbose] [--file COPIED-FROM.md]
#
#   --check    Report-only mode (default). Always exits 0.
#   --verbose  Show full diff for each drifted file.
#   --file     Path to COPIED-FROM.md (default: ./COPIED-FROM.md)
#
# ─────────────────────────────────────────────────────────────────────
# CRITICAL INVARIANT: THIS SCRIPT MUST ALWAYS EXIT 0
# ─────────────────────────────────────────────────────────────────────
# This is a reporting/advisory tool, not a blocking gate. Drift is
# logged and reported but never fails the calling process.
#
# Shell injection guard: upstream repo/path values from COPIED-FROM.md
# are passed only as arguments to `gh api` URL paths — never eval'd or
# interpolated into shell commands that execute arbitrary code.

trap 'exit 0' ERR EXIT

set +e

# ── Argument parsing ─────────────────────────────────────────────────
VERBOSE=0
REGISTRY_FILE="COPIED-FROM.md"

for arg in "$@"; do
  case "$arg" in
    --verbose) VERBOSE=1 ;;
    --check)   ;;  # default mode, no-op
    --help)
      cat <<'EOF'
Usage: check-copy-drift.sh [--check] [--verbose] [--file PATH]

  --check    Report-only mode (default). Always exits 0.
  --verbose  Show full diff for each drifted file.
  --file PATH  Path to COPIED-FROM.md (default: ./COPIED-FROM.md)

Reads COPIED-FROM.md, fetches upstream content via gh api, reports drift.
EOF
      exit 0
      ;;
    --file)    ;;  # handled below with shift pattern
  esac
done

# Handle --file with value
args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
  if [ "${args[$i]}" = "--file" ] && [ -n "${args[$((i+1))]}" ]; then
    REGISTRY_FILE="${args[$((i+1))]}"
  fi
done

# ── Resolve registry file ────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd)"

# Support relative and absolute paths
if [[ "$REGISTRY_FILE" != /* ]]; then
  # Try project root first, then cwd
  if [ -f "$PROJECT_ROOT/$REGISTRY_FILE" ]; then
    REGISTRY_FILE="$PROJECT_ROOT/$REGISTRY_FILE"
  elif [ -f "$REGISTRY_FILE" ]; then
    REGISTRY_FILE="$(pwd)/$REGISTRY_FILE"
  fi
fi

# ── Check prerequisites ───────────────────────────────────────────────
if ! command -v gh >/dev/null 2>&1; then
  echo "check-copy-drift: WARNING: gh CLI not found. Install GitHub CLI to enable drift detection."
  echo "  https://cli.github.com/"
  exit 0
fi

# ── Check registry file ──────────────────────────────────────────────
if [ ! -f "$REGISTRY_FILE" ]; then
  echo "check-copy-drift: no COPIED-FROM.md found — nothing to check."
  echo "  Create COPIED-FROM.md from templates/COPIED-FROM.md.tmpl to register copied files."
  exit 0
fi

# ── Parse COPIED-FROM.md table via python3 ────────────────────────────
# Inputs: REGISTRY_FILE path (env)
# Output: TSV lines: local_file TAB upstream_repo TAB upstream_path TAB commit TAB policy
ENTRIES=$(REGISTRY_FILE="$REGISTRY_FILE" python3 -c '
import os, sys, re

registry = os.environ.get("REGISTRY_FILE", "COPIED-FROM.md")

try:
    with open(registry) as fh:
        content = fh.read()
except Exception as e:
    sys.exit(0)

# Find markdown table rows: | col | col | col | col | col |
# Skip header rows (contain "---" or "로컬 파일")
rows = []
for line in content.splitlines():
    line = line.strip()
    if not line.startswith("|"):
        continue
    cols = [c.strip().strip("`") for c in line.split("|")]
    # Remove empty first/last elements from split
    cols = [c for c in cols if c]
    if len(cols) < 5:
        continue
    # Skip header rows
    if "---" in cols[0] or "로컬 파일" in cols[0] or "local" in cols[0].lower():
        continue
    # Skip example rows (contain placeholder text)
    local_file, upstream_repo, upstream_path, commit, policy = cols[0], cols[1], cols[2], cols[3], cols[4]
    if "upstream-repo" in upstream_repo or "owner/" in upstream_repo and "upstream" in upstream_repo:
        continue
    if not local_file or not upstream_repo or not upstream_path:
        continue
    # Emit TSV
    print(f"{local_file}\t{upstream_repo}\t{upstream_path}\t{commit}\t{policy}")
' 2>/dev/null)

if [ -z "$ENTRIES" ]; then
  echo "check-copy-drift: COPIED-FROM.md has no registered entries — nothing to check."
  exit 0
fi

# ── Process each entry ───────────────────────────────────────────────
DRIFT_COUNT=0
TOTAL_COUNT=0
SKIP_COUNT=0

while IFS=$'\t' read -r LOCAL_FILE UPSTREAM_REPO UPSTREAM_PATH COMMIT POLICY; do
  [ -z "$LOCAL_FILE" ] && continue
  [ -z "$UPSTREAM_REPO" ] && continue
  [ -z "$UPSTREAM_PATH" ] && continue

  TOTAL_COUNT=$((TOTAL_COUNT + 1))

  # Skip entries with ignore policy
  if [ "$POLICY" = "ignore" ]; then
    SKIP_COUNT=$((SKIP_COUNT + 1))
    [ "$VERBOSE" -eq 1 ] && echo "  SKIP (ignore): $LOCAL_FILE"
    continue
  fi

  # Resolve local file path
  LOCAL_PATH="$LOCAL_FILE"
  if [[ "$LOCAL_PATH" != /* ]]; then
    LOCAL_PATH="$PROJECT_ROOT/$LOCAL_FILE"
  fi

  if [ ! -f "$LOCAL_PATH" ]; then
    echo "  WARN: local file not found: $LOCAL_FILE"
    continue
  fi

  # Fetch upstream content via gh api
  # URL-encode the path by replacing spaces with %20 (paths shouldn't have spaces but be safe)
  UPSTREAM_PATH_ENC="${UPSTREAM_PATH// /%20}"
  # Strip leading slash if present
  UPSTREAM_PATH_ENC="${UPSTREAM_PATH_ENC#/}"

  UPSTREAM_CONTENT=$(gh api "repos/${UPSTREAM_REPO}/contents/${UPSTREAM_PATH_ENC}" \
    --jq '.content' 2>/dev/null | base64 -d 2>/dev/null)
  GH_RC=$?

  if [ $GH_RC -ne 0 ] || [ -z "$UPSTREAM_CONTENT" ]; then
    echo "  WARN: could not fetch upstream: ${UPSTREAM_REPO}/${UPSTREAM_PATH_ENC}"
    SKIP_COUNT=$((SKIP_COUNT + 1))
    continue
  fi

  # Diff local vs upstream
  DIFF_OUTPUT=$(diff <(cat "$LOCAL_PATH") <(printf '%s' "$UPSTREAM_CONTENT") 2>/dev/null)
  DIFF_RC=$?

  if [ $DIFF_RC -eq 0 ]; then
    [ "$VERBOSE" -eq 1 ] && echo "  OK:   $LOCAL_FILE (no drift)"
  else
    DRIFT_COUNT=$((DRIFT_COUNT + 1))
    DIFF_LINES=$(printf '%s' "$DIFF_OUTPUT" | wc -l | tr -d ' ')
    echo "  DRIFT: $LOCAL_FILE"
    echo "         upstream: ${UPSTREAM_REPO}/${UPSTREAM_PATH}"
    echo "         policy: ${POLICY:-manual}  |  diff lines: ${DIFF_LINES}"
    if [ "$VERBOSE" -eq 1 ]; then
      echo "--- diff (local vs upstream) ---"
      printf '%s\n' "$DIFF_OUTPUT"
      echo "--- end diff ---"
    fi
  fi

done <<< "$ENTRIES"

# ── Summary ──────────────────────────────────────────────────────────
echo ""
echo "check-copy-drift: checked $TOTAL_COUNT entr$([ "$TOTAL_COUNT" -eq 1 ] && echo 'y' || echo 'ies') — ${DRIFT_COUNT} drifted, ${SKIP_COUNT} skipped"
if [ "$DRIFT_COUNT" -gt 0 ]; then
  echo "  Run with --verbose to see full diffs."
  echo "  Update COPIED-FROM.md sync policy to 'ignore' for intentional forks."
fi

# Always exit 0 — the most important line.
exit 0
