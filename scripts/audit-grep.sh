#!/usr/bin/env bash
# scripts/audit-grep.sh — JSONL 감사 로그 검색/필터 도구
#
# idea-factory v8 item 1.4 (감사 로그 post-session 분석 도구)
# .claude/audit/YYYY-MM-DD.jsonl 파일을 jq로 쿼리한다.
#
# 사용법:
#   bash scripts/audit-grep.sh [OPTIONS]
#
# 옵션:
#   --dir DIR          감사 로그 디렉터리 (기본: .claude/audit/ | AUDIT_DIR 환경변수)
#   --date YYYY-MM-DD  특정 날짜 (기본: 오늘)
#   --all              AUDIT_DIR 하위 모든 YYYY-MM-DD.jsonl 스캔
#   --since N{s,m,h,d} 최근 N초/분/시/일 내 이벤트 (예: --since 2h)
#   --tool NAME        tags 필드에 NAME이 포함된 이벤트 (Bash, deploy, rm-rf 등)
#   --grep PATTERN     cmd 필드에 PATTERN(정규식) 매칭 이벤트
#   --session ID       session 필드가 ID인 이벤트
#   --top N            가장 빈번한 명령어 상위 N개 집계 출력
#   --summary          세션별 이벤트 수 + 첫/마지막 ts 요약
#   --json             결과를 원시 JSONL로 출력 (기본: 1줄 요약 포맷)
#   -h, --help         이 도움말 출력
#
# 종료 코드:
#   0  결과 있음 또는 정상 빈 결과
#   2  인자 오류
#
# 예시:
#   bash scripts/audit-grep.sh --since 2h --grep "npm install"
#   bash scripts/audit-grep.sh --all --tool rm-rf
#   bash scripts/audit-grep.sh --date 2026-04-17 --session abc123 --json
#   bash scripts/audit-grep.sh --all --top 10
#   bash scripts/audit-grep.sh --all --summary

# NOTE: -e 미사용 — --top/--summary 파이프 끝에서 비어도 nonzero 발생 방지
set -uo pipefail

# ── jq 필수 확인 ──────────────────────────────────────────────────
if ! command -v jq >/dev/null 2>&1; then
  echo "audit-grep: 오류 — jq가 설치되어 있지 않습니다." >&2
  echo "  설치: brew install jq  또는  apt-get install jq" >&2
  exit 2
fi

# ── 기본값 ────────────────────────────────────────────────────────
AUDIT_DIR="${AUDIT_DIR:-.claude/audit}"
DATE_TARGET="$(date +%Y-%m-%d 2>/dev/null || echo '')"
ALL_FILES=0
SINCE=""
TOOL_FILTER=""
GREP_PATTERN=""
SESSION_FILTER=""
TOP_N=""
SUMMARY_MODE=0
JSON_OUTPUT=0

# ── 인자 파싱 ─────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
  case "$1" in
    --dir)
      [ -z "${2-}" ] && { echo "audit-grep: --dir 에 값이 필요합니다" >&2; exit 2; }
      AUDIT_DIR="$2"; shift 2 ;;
    --date)
      [ -z "${2-}" ] && { echo "audit-grep: --date 에 값이 필요합니다" >&2; exit 2; }
      DATE_TARGET="$2"; shift 2 ;;
    --all)
      ALL_FILES=1; shift ;;
    --since)
      [ -z "${2-}" ] && { echo "audit-grep: --since 에 값이 필요합니다 (예: 2h)" >&2; exit 2; }
      SINCE="$2"; shift 2 ;;
    --tool)
      [ -z "${2-}" ] && { echo "audit-grep: --tool 에 값이 필요합니다" >&2; exit 2; }
      TOOL_FILTER="$2"; shift 2 ;;
    --grep)
      [ -z "${2-}" ] && { echo "audit-grep: --grep 에 패턴이 필요합니다" >&2; exit 2; }
      GREP_PATTERN="$2"; shift 2 ;;
    --session)
      [ -z "${2-}" ] && { echo "audit-grep: --session 에 ID가 필요합니다" >&2; exit 2; }
      SESSION_FILTER="$2"; shift 2 ;;
    --top)
      [ -z "${2-}" ] && { echo "audit-grep: --top 에 숫자가 필요합니다" >&2; exit 2; }
      TOP_N="$2"; shift 2 ;;
    --summary)
      SUMMARY_MODE=1; shift ;;
    --json)
      JSON_OUTPUT=1; shift ;;
    -h|--help)
      sed -n '3,30p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *)
      echo "audit-grep: 알 수 없는 옵션: $1" >&2
      echo "  사용법: bash scripts/audit-grep.sh --help" >&2
      exit 2 ;;
  esac
done

# ── 감사 디렉터리 확인 ────────────────────────────────────────────
if [ ! -d "$AUDIT_DIR" ]; then
  echo "audit-grep: 감사 로그 디렉터리가 없습니다: $AUDIT_DIR" >&2
  echo "  Claude Code 세션을 한 번 실행하면 자동으로 생성됩니다." >&2
  exit 0
fi

# ── 대상 파일 목록 구성 ───────────────────────────────────────────
if [ "$ALL_FILES" -eq 1 ]; then
  # 모든 YYYY-MM-DD.jsonl 파일 (날짜순)
  mapfile -t LOG_FILES < <(
    find "$AUDIT_DIR" -maxdepth 1 -name '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].jsonl' \
      2>/dev/null | sort
  )
else
  LOG_FILES=("${AUDIT_DIR}/${DATE_TARGET}.jsonl")
fi

# 존재하는 파일만 걸러냄
VALID_FILES=()
for f in "${LOG_FILES[@]+"${LOG_FILES[@]}"}"; do
  [ -f "$f" ] && VALID_FILES+=("$f")
done

if [ ${#VALID_FILES[@]} -eq 0 ]; then
  if [ "$ALL_FILES" -eq 1 ]; then
    echo "audit-grep: $AUDIT_DIR 에 JSONL 파일이 없습니다." >&2
  else
    echo "audit-grep: 로그 없음 — ${DATE_TARGET}.jsonl 파일이 없습니다." >&2
  fi
  exit 0
fi

# ── --since: 기준 타임스탬프 계산 ────────────────────────────────
SINCE_EPOCH=0
if [ -n "$SINCE" ]; then
  num="${SINCE%[smhd]}"
  unit="${SINCE: -1}"
  if ! [[ "$num" =~ ^[0-9]+$ ]]; then
    echo "audit-grep: --since 형식 오류 (예: 30m, 2h, 1d)" >&2
    exit 2
  fi
  case "$unit" in
    s) secs=$num ;;
    m) secs=$((num * 60)) ;;
    h) secs=$((num * 3600)) ;;
    d) secs=$((num * 86400)) ;;
    *) echo "audit-grep: --since 단위는 s/m/h/d 중 하나여야 합니다" >&2; exit 2 ;;
  esac
  SINCE_EPOCH=$(( $(date +%s) - secs ))
fi

# ── jq 필터 구성 ──────────────────────────────────────────────────
# 각 조건을 select()로 연결
build_filter() {
  local f="."
  local conditions=()

  if [ "$SINCE_EPOCH" -gt 0 ]; then
    # ts 필드를 epoch로 변환하여 비교
    conditions+=("(.ts | strptime(\"%Y-%m-%dT%H:%M:%SZ\") | mktime) >= ${SINCE_EPOCH}")
  fi

  if [ -n "$TOOL_FILTER" ]; then
    conditions+=("(.tags | test(\"${TOOL_FILTER}\"; \"i\"))")
  fi

  if [ -n "$GREP_PATTERN" ]; then
    conditions+=("(.cmd | test(\"${GREP_PATTERN}\"; \"i\"))")
  fi

  if [ -n "$SESSION_FILTER" ]; then
    conditions+=("(.session == \"${SESSION_FILTER}\")")
  fi

  if [ ${#conditions[@]} -gt 0 ]; then
    local joined
    joined="$(printf ' and %s' "${conditions[@]}")"
    joined="${joined# and }"
    f="select(${joined})"
  fi

  echo "$f"
}

JQ_FILTER="$(build_filter)"

# ── 모드별 처리 ───────────────────────────────────────────────────

# --top N: 빈도 집계
if [ -n "$TOP_N" ]; then
  if ! [[ "$TOP_N" =~ ^[0-9]+$ ]]; then
    echo "audit-grep: --top 에는 양의 정수가 필요합니다" >&2
    exit 2
  fi
  cat "${VALID_FILES[@]}" \
    | jq -r "${JQ_FILTER} | .cmd" 2>/dev/null \
    | sort | uniq -c | sort -rn \
    | head -n "$TOP_N" \
    | awk '{ cnt=$1; $1=""; cmd=substr($0,2); printf "%5d  %s\n", cnt, cmd }'
  exit 0
fi

# --summary: 세션별 요약
if [ "$SUMMARY_MODE" -eq 1 ]; then
  cat "${VALID_FILES[@]}" \
    | jq -r "${JQ_FILTER} | [.session, .ts] | @tsv" 2>/dev/null \
    | sort \
    | awk -F'\t' '
      {
        sess=$1; ts=$2
        count[sess]++
        if (!(sess in first)) first[sess]=ts
        last[sess]=ts
      }
      END {
        for (s in count)
          printf "session=%-24s  events=%4d  first=%s  last=%s\n", s, count[s], first[s], last[s]
      }
    ' | sort
  exit 0
fi

# 기본/--json 모드: 이벤트 출력
if [ "$JSON_OUTPUT" -eq 1 ]; then
  cat "${VALID_FILES[@]}" \
    | jq -c "${JQ_FILTER}" 2>/dev/null
else
  cat "${VALID_FILES[@]}" \
    | jq -r "${JQ_FILTER} | \"\(.ts)  [\(.session | .[0:8])]  tags=[\(.tags)]  \(.cmd | .[0:120])\"" \
    2>/dev/null
fi

exit 0
