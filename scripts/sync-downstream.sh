#!/usr/bin/env bash
# sync-downstream.sh — Template-to-downstream sync engine
#
# idea-factory v8 item 7.4
#
# Usage:
#   bash scripts/sync-downstream.sh --check          # drift 리포트만
#   bash scripts/sync-downstream.sh --apply           # drift 감지 + PR 생성
#   bash scripts/sync-downstream.sh --check --repo signalplay  # 특정 레포만
#
# Exit: always 0 (idea-factory invariant)

set +e
trap 'exit 0' ERR

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MODE="check"
TARGET_REPO=""
VERBOSE=false

# ── Parse arguments ──────────────────────────────────────────────
while [ $# -gt 0 ]; do
  case "$1" in
    --check)  MODE="check"; shift ;;
    --apply)  MODE="apply"; shift ;;
    --repo)   TARGET_REPO="$2"; shift 2 ;;
    --verbose) VERBOSE=true; shift ;;
    -h|--help)
      echo "Usage: sync-downstream.sh [--check|--apply] [--repo NAME] [--verbose]"
      echo ""
      echo "Modes:"
      echo "  --check   Drift report only (default)"
      echo "  --apply   Create PRs for drifted repos"
      echo ""
      echo "Options:"
      echo "  --repo NAME   Target specific repo"
      echo "  --verbose     Show file-level diffs"
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; shift ;;
  esac
done

# ── Validate prerequisites ───────────────────────────────────────
if ! command -v gh >/dev/null 2>&1; then
  echo "Error: gh CLI not found" >&2
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "Error: python3 not found" >&2
  exit 0
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "Error: gh not authenticated" >&2
  exit 0
fi

REGISTRY="$SCRIPT_DIR/downstream-registry.json"
MANIFEST="$SCRIPT_DIR/sync-manifest.json"

if [ ! -f "$REGISTRY" ] || [ ! -f "$MANIFEST" ]; then
  echo "Error: registry or manifest not found" >&2
  exit 0
fi

# ── Run python3 sync engine ─────────────────────────────────────
python3 "$SCRIPT_DIR/scripts/sync-lib.py" \
  --mode "$MODE" \
  --registry "$REGISTRY" \
  --manifest "$MANIFEST" \
  --templates "$SCRIPT_DIR" \
  ${TARGET_REPO:+--repo "$TARGET_REPO"} \
  ${VERBOSE:+--verbose} \
  2>&1 || true

exit 0
