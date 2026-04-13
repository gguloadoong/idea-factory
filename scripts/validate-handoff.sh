#!/usr/bin/env bash
# validate-handoff.sh — Auto-compact loss validation for handoff docs
#
# Reads a handoff document and checks whether core invariants/keywords from a
# reference file are mentioned. Outputs a coverage score so authors know
# whether their handoff doc would survive a context-compaction event.
#
# Advisory only — always exits 0 (idea-factory invariant).
#
# Usage:
#   bash scripts/validate-handoff.sh
#   bash scripts/validate-handoff.sh --handoff path/to/handoff.md --invariants path/to/CLAUDE.md
#   bash scripts/validate-handoff.sh --verbose
#
# Env overrides:
#   HANDOFF_FILE      path to handoff document
#   INVARIANTS_FILE   path to invariants/CLAUDE.md reference

set +e
trap 'exit 0' ERR EXIT

# --- Color helpers ---
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

info()  { printf "${GREEN}[validate-handoff] %s${NC}\n" "$1"; }
warn()  { printf "${YELLOW}[validate-handoff] WARN: %s${NC}\n" "$1" >&2; }
note()  { printf "${CYAN}[validate-handoff] %s${NC}\n" "$1"; }

# --- Defaults ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

HANDOFF_FILE="${HANDOFF_FILE:-$ROOT_DIR/handoff.md}"
INVARIANTS_FILE="${INVARIANTS_FILE:-$ROOT_DIR/CLAUDE.md}"
VERBOSE=0
THRESHOLD=60   # warn if coverage below this percent

# --- Argument parsing (no eval, no shell injection) ---
while [ $# -gt 0 ]; do
  case "$1" in
    --handoff)
      shift
      HANDOFF_FILE="$1"
      ;;
    --invariants)
      shift
      INVARIANTS_FILE="$1"
      ;;
    --verbose)
      VERBOSE=1
      ;;
    --threshold)
      shift
      # Sanitize: accept only numeric values
      case "$1" in
        ''|*[!0-9]*) warn "invalid --threshold value '$1', using default $THRESHOLD" ;;
        *) THRESHOLD="$1" ;;
      esac
      ;;
    *)
      warn "unknown argument: $1 (ignored)"
      ;;
  esac
  shift
done

# -----------------------------------------------------------------------
# File checks
# -----------------------------------------------------------------------

if [ ! -f "$HANDOFF_FILE" ]; then
  warn "handoff file not found: $HANDOFF_FILE"
  info "nothing to validate — exiting gracefully"
  exit 0
fi

if [ ! -f "$INVARIANTS_FILE" ]; then
  warn "invariants file not found: $INVARIANTS_FILE"
  info "nothing to validate — exiting gracefully"
  exit 0
fi

# Check for empty files
handoff_size=$(wc -c < "$HANDOFF_FILE" 2>/dev/null || echo 0)
invariants_size=$(wc -c < "$INVARIANTS_FILE" 2>/dev/null || echo 0)

if [ "$handoff_size" -eq 0 ]; then
  warn "handoff file is empty: $HANDOFF_FILE"
  info "nothing to validate — exiting gracefully"
  exit 0
fi

if [ "$invariants_size" -eq 0 ]; then
  warn "invariants file is empty: $INVARIANTS_FILE"
  info "nothing to validate — exiting gracefully"
  exit 0
fi

# -----------------------------------------------------------------------
# Extract keywords from invariants file
#
# Strategy: pull meaningful tokens from:
#   - Lines starting with "- " or "* " (list items)
#   - Lines with ## headings
#   - Lines containing "금지" (forbidden), "필수" (required), "보장" (guarantee)
#   - Lines with backtick code references
#
# We extract distinct lowercase words of 3+ chars, excluding stop words.
# -----------------------------------------------------------------------

STOP_WORDS="the and for are with that this from have will not you your its are was were been being have has had do does did shall should would could may might must can"

extract_keywords() {
  local file="$1"
  # Extract candidate lines
  grep -E '(^[-*] |^#{1,4} |금지|필수|보장|exit 0|절대|반드시|`[^`]+`)' "$file" 2>/dev/null \
    | sed 's/```[^`]*```//g' \
    | sed 's/`\([^`]*\)`/\1/g' \
    | tr '[:upper:]' '[:lower:]' \
    | tr -cs 'a-z0-9가-힣_.-' ' ' \
    | tr ' ' '\n' \
    | grep -E '^.{3,}$' \
    | sort -u
}

# Build keyword list into a temp variable (newline-separated)
KEYWORDS=$(extract_keywords "$INVARIANTS_FILE")

KEYWORD_COUNT=$(echo "$KEYWORDS" | grep -c '.' 2>/dev/null || echo 0)

if [ "$KEYWORD_COUNT" -eq 0 ]; then
  warn "no keywords extracted from invariants file — cannot score"
  info "exiting gracefully"
  exit 0
fi

# -----------------------------------------------------------------------
# Check handoff coverage
# -----------------------------------------------------------------------

HANDOFF_LOWER=$(tr '[:upper:]' '[:lower:]' < "$HANDOFF_FILE" 2>/dev/null || true)

FOUND=0
MISSING=""

while IFS= read -r kw; do
  [ -z "$kw" ] && continue
  # Skip stop words
  skip=0
  for sw in $STOP_WORDS; do
    if [ "$kw" = "$sw" ]; then
      skip=1
      break
    fi
  done
  [ "$skip" -eq 1 ] && continue

  if echo "$HANDOFF_LOWER" | grep -qF "$kw"; then
    FOUND=$((FOUND + 1))
  else
    if [ -z "$MISSING" ]; then
      MISSING="$kw"
    else
      MISSING="$MISSING
$kw"
    fi
  fi
done <<< "$KEYWORDS"

MISSING_COUNT=$(echo "$MISSING" | grep -c '.' 2>/dev/null || echo 0)
CHECKED=$((FOUND + MISSING_COUNT))

if [ "$CHECKED" -eq 0 ]; then
  warn "no checkable keywords after filtering stop words"
  info "exiting gracefully"
  exit 0
fi

# -----------------------------------------------------------------------
# Score and report
# -----------------------------------------------------------------------

# Integer percent: (FOUND * 100) / CHECKED
PERCENT=$(( (FOUND * 100) / CHECKED ))

echo ""
info "handoff:    $HANDOFF_FILE"
info "invariants: $INVARIANTS_FILE"
echo ""
info "핵심 불변 조건 ${CHECKED}개 중 ${FOUND}개 핸드오프 문서에서 언급됨 (${PERCENT}%)"
echo ""

if [ "$PERCENT" -ge "$THRESHOLD" ]; then
  info "커버리지 OK — 핸드오프 문서가 핵심 불변 조건을 충분히 포함합니다 (임계값: ${THRESHOLD}%)"
else
  warn "커버리지 미달 — ${PERCENT}% < 임계값 ${THRESHOLD}%"
  warn "핸드오프 문서에 누락된 불변 조건을 추가하세요"
fi

if [ "$VERBOSE" -eq 1 ] && [ -n "$MISSING" ]; then
  echo ""
  note "누락된 불변 조건 키워드 목록:"
  echo "$MISSING" | while IFS= read -r kw; do
    [ -n "$kw" ] && printf "  - %s\n" "$kw"
  done
fi

echo ""
exit 0
