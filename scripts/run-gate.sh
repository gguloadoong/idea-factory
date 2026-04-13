#!/usr/bin/env bash
# run-gate.sh — Rule-driven reviewer gate sizing
#
# 변경 파일 패턴에 따라 gate-rules.yml 을 참조해 동적으로 리뷰어 세트를 선택한다.
# Advisory only — always exits 0 (idea-factory invariant).
#
# Usage:
#   bash scripts/run-gate.sh            # 변경 파일 분석 후 리뷰어 출력
#   bash scripts/run-gate.sh --dry-run  # 리뷰어 선택 시뮬레이션만 (실제 게이트 미실행)
#
# GATE_RULES env var 로 rules 파일 경로 오버라이드 가능.
# GATE_FILES env var 로 변경 파일 목록 직접 주입 가능 (테스트용, newline 구분).

set +e
trap 'exit 0' ERR EXIT

# --- Color helpers ---
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { printf "${GREEN}[run-gate] %s${NC}\n" "$1"; }
warn()  { printf "${YELLOW}[run-gate] WARN: %s${NC}\n" "$1" >&2; }
note()  { printf "${CYAN}[run-gate] %s${NC}\n" "$1"; }

DRY_RUN=0
for arg in "$@"; do
  [ "$arg" = "--dry-run" ] && DRY_RUN=1
done

# --- Locate gate-rules.yml ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RULES_FILE="${GATE_RULES:-$ROOT_DIR/templates/gate-rules.yml}"

# -----------------------------------------------------------------------
# YAML parser (stdlib only — no PyYAML)
#
# Parses gate-rules.yml into parallel arrays:
#   RULE_MATCH_*   — space-separated list of patterns for rule N
#   RULE_REVIEWERS_* — space-separated reviewers for rule N
#   RULE_REASON_*  — reason string for rule N
#   RULE_COUNT     — total number of rules
#   DEFAULT_REVIEWERS / DEFAULT_REASON — default section
# -----------------------------------------------------------------------

parse_rules() {
  local file="$1"

  RULE_COUNT=0
  DEFAULT_REVIEWERS=""
  DEFAULT_REASON=""

  if [ ! -f "$file" ]; then
    warn "gate-rules.yml not found at: $file — using built-in default"
    DEFAULT_REVIEWERS="architect code-reviewer"
    DEFAULT_REASON="기본 리뷰 세트 (fallback)"
    return
  fi

  local in_rules=0
  local in_default=0
  local in_match_list=0
  local current_match=""
  local current_reviewers=""
  local current_reason=""
  local idx=0

  # Flush the current rule into arrays
  flush_rule() {
    if [ -n "$current_match" ] || [ -n "$current_reviewers" ]; then
      eval "RULE_MATCH_${idx}=\"\$current_match\""
      eval "RULE_REVIEWERS_${idx}=\"\$current_reviewers\""
      eval "RULE_REASON_${idx}=\"\$current_reason\""
      idx=$((idx + 1))
      RULE_COUNT=$((RULE_COUNT + 1))
    fi
    current_match=""
    current_reviewers=""
    current_reason=""
    in_match_list=0
  }

  while IFS= read -r raw_line; do
    # Strip trailing whitespace
    line="${raw_line%"${raw_line##*[![:space:]]}"}"

    # Skip blank lines and comments
    case "$line" in
      ""|\#*) continue ;;
    esac

    # Detect top-level sections
    case "$line" in
      "rules:")
        in_rules=1; in_default=0
        continue
        ;;
      "default:")
        # Flush any pending rule
        if [ "$in_rules" -eq 1 ]; then
          flush_rule
        fi
        in_rules=0; in_default=1
        continue
        ;;
    esac

    # ----- rules section -----
    if [ "$in_rules" -eq 1 ]; then
      case "$line" in
        "  - match:"*)
          # New rule block starts — flush previous
          flush_rule
          # Inline match value? e.g.   - match: "*.md"  or  - match: ["a", "b"]
          val="${line#*match:}"
          val="${val#"${val%%[! ]*}"}"   # ltrim
          if echo "$val" | grep -q '^\['; then
            # Inline list: parse it into space-separated patterns
            val="${val#\[}" ; val="${val%\]}"
            current_match=""
            while IFS=',' read -ra tokens; do
              for token in "${tokens[@]}"; do
                token="${token#"${token%%[! ]*}"}"
                token="${token%"${token##*[! ]}"}"
                token="${token#\"}" ; token="${token%\"}"
                token="${token#\'}" ; token="${token%\'}"
                [ -z "$token" ] && continue
                if [ -z "$current_match" ]; then
                  current_match="$token"
                else
                  current_match="$current_match $token"
                fi
              done
            done <<< "$val"
            in_match_list=0
          elif [ -n "$val" ]; then
            val="${val#\"}" ; val="${val%\"}"
            val="${val#\'}" ; val="${val%\'}"
            current_match="$val"
            in_match_list=0
          else
            in_match_list=1
          fi
          ;;
        "    match:"*)
          # Indented match (rare, same handling)
          val="${line#*match:}"
          val="${val#"${val%%[! ]*}"}"
          val="${val#\"}"
          val="${val%\"}"
          current_match="$val"
          in_match_list=0
          ;;
        "    - "*)
          # List item — could be match list item or reviewers list item
          if [ "$in_match_list" -eq 1 ]; then
            item="${line#*    - }"
            item="${item#\"}"
            item="${item%\"}"
            item="${item#\'}"
            item="${item%\'}"
            if [ -z "$current_match" ]; then
              current_match="$item"
            else
              current_match="$current_match $item"
            fi
          else
            # Reviewers list item
            item="${line#*    - }"
            item="${item#"${item%%[! ]*}"}"
            if [ -z "$current_reviewers" ]; then
              current_reviewers="$item"
            else
              current_reviewers="$current_reviewers $item"
            fi
          fi
          ;;
        "    reviewers:"*)
          in_match_list=0
          val="${line#*reviewers:}"
          val="${val#"${val%%[! ]*}"}"
          # Inline list: [a, b, c]
          if echo "$val" | grep -q '^\['; then
            val="${val#\[}"
            val="${val%\]}"
            # Remove quotes and spaces around commas
            # Split on commas, strip surrounding whitespace/quotes per token
            current_reviewers=""
            while IFS=',' read -ra tokens; do
              for token in "${tokens[@]}"; do
                token="${token#"${token%%[! ]*}"}"
                token="${token%"${token##*[! ]}"}"
                token="${token#\"}" ; token="${token%\"}"
                token="${token#\'}" ; token="${token%\'}"
                [ -z "$token" ] && continue
                if [ -z "$current_reviewers" ]; then
                  current_reviewers="$token"
                else
                  current_reviewers="$current_reviewers $token"
                fi
              done
            done <<< "$val"
          fi
          # empty list [] stays empty
          ;;
        "    reason:"*)
          val="${line#*reason:}"
          val="${val#"${val%%[! ]*}"}"
          val="${val#\"}"
          val="${val%\"}"
          current_reason="$val"
          ;;
      esac
    fi

    # ----- default section -----
    if [ "$in_default" -eq 1 ]; then
      case "$line" in
        "  reviewers:"*)
          val="${line#*reviewers:}"
          val="${val#"${val%%[! ]*}"}"
          if echo "$val" | grep -q '^\['; then
            val="${val#\[}"
            val="${val%\]}"
            DEFAULT_REVIEWERS=""
            while IFS=',' read -ra tokens; do
              for token in "${tokens[@]}"; do
                token="${token#"${token%%[! ]*}"}"
                token="${token%"${token##*[! ]}"}"
                token="${token#\"}" ; token="${token%\"}"
                token="${token#\'}" ; token="${token%\'}"
                [ -z "$token" ] && continue
                if [ -z "$DEFAULT_REVIEWERS" ]; then
                  DEFAULT_REVIEWERS="$token"
                else
                  DEFAULT_REVIEWERS="$DEFAULT_REVIEWERS $token"
                fi
              done
            done <<< "$val"
          fi
          ;;
        "  reason:"*)
          val="${line#*reason:}"
          val="${val#"${val%%[! ]*}"}"
          val="${val#\"}"
          val="${val%\"}"
          DEFAULT_REASON="$val"
          ;;
      esac
    fi
  done < "$file"

  # Flush last rule
  if [ "$in_rules" -eq 1 ]; then
    flush_rule
  fi

  RULE_COUNT=$idx
}

# -----------------------------------------------------------------------
# Glob matching helper
#
# match_pattern FILE PATTERN
#   Returns 0 if FILE matches PATTERN (fnmatch-style via bash case).
#   Supports:
#     *     — any chars within a path segment
#     **    — any path depth
#     {a,b} — brace expansion (expanded before matching)
#     ?     — single char
# -----------------------------------------------------------------------

expand_braces() {
  # Expand {a,b,c} in a glob pattern into multiple patterns (space-separated).
  # Only handles one level of braces; nested braces not needed here.
  local pat="$1"
  if ! echo "$pat" | grep -q '{'; then
    echo "$pat"
    return
  fi
  local pre mid post
  pre="${pat%%\{*}"
  mid="${pat#*\{}"
  mid="${mid%%\}*}"
  post="${pat#*\}}"
  IFS=',' read -ra parts <<< "$mid"
  local result=""
  for part in "${parts[@]}"; do
    result="$result ${pre}${part}${post}"
  done
  echo "$result"
}

match_single_pattern() {
  local file="$1"
  local pat="$2"

  # Convert ** glob to a sentinel, then use case for the rest.
  # Strategy: try bash case with the pattern; for ** we test with python-free logic.

  # If pattern contains **, convert to case-compatible form using recursive check.
  if echo "$pat" | grep -q '\*\*'; then
    # Split pattern on **
    local before_dstar after_dstar
    before_dstar="${pat%%\*\**}"
    after_dstar="${pat#*\*\*}"
    after_dstar="${after_dstar#/}"  # strip leading slash after **

    local file_rest="$file"

    # before_dstar must match the start of file
    if [ -n "$before_dstar" ]; then
      # before_dstar is a prefix pattern (may contain * but not **)
      case "$file" in
        $before_dstar*) file_rest="${file#$before_dstar}" ;;
        *) return 1 ;;
      esac
    fi

    # after_dstar must match the end of file (suffix)
    if [ -z "$after_dstar" ]; then
      return 0
    fi

    # after_dstar may itself be a glob; try matching suffix across all path depths
    # by testing if any suffix of file_rest matches after_dstar
    local tmp="$file_rest"
    while true; do
      case "$tmp" in
        $after_dstar) return 0 ;;
      esac
      # Try stripping one path segment from the front
      if echo "$tmp" | grep -q '/'; then
        tmp="${tmp#*/}"
      else
        break
      fi
    done
    return 1
  fi

  # No ** — use bash case for standard glob matching
  case "$file" in
    $pat) return 0 ;;
    *) return 1 ;;
  esac
}

file_matches_pattern() {
  local file="$1"
  local pat="$2"

  # Expand braces first
  local expanded
  expanded=$(expand_braces "$pat")
  for p in $expanded; do
    if match_single_pattern "$file" "$p"; then
      return 0
    fi
  done
  return 1
}

# -----------------------------------------------------------------------
# Union of reviewer sets
# -----------------------------------------------------------------------

add_reviewers() {
  # Add reviewers from $2 into global SELECTED_REVIEWERS (space-separated, dedup)
  local new="$1"
  for r in $new; do
    if ! echo " $SELECTED_REVIEWERS " | grep -q " $r "; then
      if [ -z "$SELECTED_REVIEWERS" ]; then
        SELECTED_REVIEWERS="$r"
      else
        SELECTED_REVIEWERS="$SELECTED_REVIEWERS $r"
      fi
    fi
  done
}

# -----------------------------------------------------------------------
# Get changed files
# -----------------------------------------------------------------------

get_changed_files() {
  # Allow injection via env for testing (GATE_FILES set, even if empty)
  if [ "${GATE_FILES+set}" = "set" ]; then
    echo "$GATE_FILES"
    return
  fi

  if ! command -v git >/dev/null 2>&1; then
    warn "git not found — cannot determine changed files"
    return
  fi

  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    warn "not a git repository — cannot determine changed files"
    return
  fi

  # Try: staged files first, then HEAD~1
  local staged
  staged=$(git diff --cached --name-only 2>/dev/null)
  if [ -n "$staged" ]; then
    echo "$staged"
    return
  fi

  # Fall back to HEAD~1 diff
  if git rev-parse --verify HEAD~1 >/dev/null 2>&1; then
    git diff --name-only HEAD~1 2>/dev/null
    return
  fi

  # Only one commit — compare to empty tree
  git diff --name-only "$(git hash-object -t tree /dev/null)" HEAD 2>/dev/null || true
}

# -----------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------

[ "$DRY_RUN" -eq 1 ] && note "dry-run mode — simulating only"

parse_rules "$RULES_FILE"

CHANGED_FILES=$(get_changed_files)

if [ -z "$CHANGED_FILES" ]; then
  info "no changed files detected — nothing to gate"
  exit 0
fi

if [ "$DRY_RUN" -eq 1 ]; then
  note "changed files:"
  echo "$CHANGED_FILES" | sed 's/^/  /'
  echo ""
fi

SELECTED_REVIEWERS=""
declare -A MATCH_REASONS 2>/dev/null || true  # bash 4+ associative array; graceful fallback below
REASONS=""

while IFS= read -r file; do
  [ -z "$file" ] && continue

  matched=0
  for i in $(seq 0 $((RULE_COUNT - 1))); do
    eval "patterns=\"\$RULE_MATCH_${i}\""
    eval "reviewers=\"\$RULE_REVIEWERS_${i}\""
    eval "reason=\"\$RULE_REASON_${i}\""

    for pat in $patterns; do
      if file_matches_pattern "$file" "$pat"; then
        matched=1
        if [ -n "$reviewers" ]; then
          add_reviewers "$reviewers"
          # Track reason (simple dedup)
          if ! echo "$REASONS" | grep -qF "$reason"; then
            REASONS="${REASONS}${reason}|"
          fi
        else
          # Explicit empty reviewer list (e.g. *.md → no review)
          :
        fi
        if [ "$DRY_RUN" -eq 1 ]; then
          if [ -n "$reviewers" ]; then
            note "  $file  →  [$reviewers]  ($reason)"
          else
            note "  $file  →  [no reviewers]  ($reason)"
          fi
        fi
        break 2  # first-match wins per file; break both loops
      fi
    done
  done

  if [ "$matched" -eq 0 ]; then
    # Apply default
    add_reviewers "$DEFAULT_REVIEWERS"
    if ! echo "$REASONS" | grep -qF "$DEFAULT_REASON"; then
      REASONS="${REASONS}${DEFAULT_REASON}|"
    fi
    if [ "$DRY_RUN" -eq 1 ]; then
      note "  $file  →  [$DEFAULT_REVIEWERS]  ($DEFAULT_REASON) [default]"
    fi
  fi
done <<< "$CHANGED_FILES"

# --- Output summary ---
echo ""
if [ -z "$SELECTED_REVIEWERS" ]; then
  info "reviewers: none (all changes are doc-only or reviewer-exempt)"
else
  info "selected reviewers: $SELECTED_REVIEWERS"
  # Print each reason
  IFS='|' read -ra reason_list <<< "$REASONS"
  for r in "${reason_list[@]}"; do
    [ -n "$r" ] && note "  reason: $r"
  done
fi

echo ""
[ "$DRY_RUN" -eq 1 ] && note "dry-run complete — no gate executed"

exit 0
