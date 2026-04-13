#!/usr/bin/env bash
# scripts/check-contract.sh — CONTRACT 규칙 위반 검사
#
# 사용법:
#   bash scripts/check-contract.sh [--rules FILE] [--path DIR] [--strict]
#
# 옵션:
#   --rules FILE   규칙 파일 (기본: templates/contract-rules/example-rules.yml)
#   --path DIR     검사 경로 (기본: 현재 디렉터리)
#   --strict       위반 발견 시 exit 1 (CI용). 기본은 exit 0.
#
# 불변식: --strict 없으면 항상 exit 0

set +e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# --- 기본값 ---
RULES_FILE="$ROOT/templates/contract-rules/example-rules.yml"
SEARCH_PATH="$ROOT"
STRICT=0

# --- 인자 파싱 ---
while [ $# -gt 0 ]; do
  case "$1" in
    --rules)
      RULES_FILE="$2"
      shift 2
      ;;
    --path)
      SEARCH_PATH="$2"
      shift 2
      ;;
    --strict)
      STRICT=1
      shift
      ;;
    *)
      echo "check-contract: 알 수 없는 옵션: $1" >&2
      shift
      ;;
  esac
done

# --- 규칙 파일 존재 확인 ---
if [ ! -f "$RULES_FILE" ]; then
  echo "check-contract: 규칙 파일 없음: $RULES_FILE" >&2
  echo "check-contract: 규칙 파일이 없으면 검사를 건너뜁니다."
  exit 0
fi

# --- YAML 파서 (stdlib only, PyYAML 없이) ---
# rules 블록에서 각 규칙의 필드를 추출하는 간단한 파서
# 형식 가정: 각 규칙은 "  - id:" 로 시작, 필드는 "    key: value"

VIOLATIONS=0

parse_and_check() {
  local rules_file="$1"
  local search_path="$2"

  # 규칙 단위로 분리 — "  - id:" 를 구분자로 사용
  local current_id=""
  local current_desc=""
  local current_pattern=""
  local current_ref=""
  local current_action="warn"
  local in_files=0
  local file_patterns=()

  # 규칙 하나를 실제로 검사하는 함수
  run_rule() {
    local id="$1"
    local desc="$2"
    local pattern="$3"
    local ref="$4"
    local -a files=("${@:5}")

    [ -z "$id" ] && return
    [ -z "$pattern" ] && return

    # files 목록이 비어 있으면 search_path 전체 검사
    if [ ${#files[@]} -eq 0 ]; then
      files=("$search_path")
    fi

    local found=0
    for glob in "${files[@]}"; do
      [ -z "$glob" ] && continue

      # brace expansion 처리: {js,ts} → 복수 패턴
      # bash brace expansion은 eval 없이는 변수로 안 됨 → find + -name 조합 사용
      local base_dir="$search_path"
      local name_part="$glob"

      # glob이 절대경로가 아니면 search_path 기준
      if [[ "$glob" != /* ]]; then
        # glob에서 디렉터리 부분과 파일 패턴 분리
        local dir_part
        dir_part="$(dirname "$glob")"
        name_part="$(basename "$glob")"
        if [ "$dir_part" = "." ] || [ "$dir_part" = "**" ]; then
          base_dir="$search_path"
        else
          # ** 포함 경로 처리
          base_dir="$search_path"
        fi
      fi

      # {ext1,ext2} 형태를 분리해서 각각 검사
      if [[ "$name_part" =~ \{([^}]+)\} ]]; then
        local exts_str="${BASH_REMATCH[1]}"
        local prefix="${name_part%%\{*}"
        local suffix="${name_part##*\}}"
        IFS=',' read -ra exts <<< "$exts_str"
        for ext in "${exts[@]}"; do
          local expanded="${prefix}${ext}${suffix}"
          # shell injection 방지: pattern을 grep -F 또는 -E로만 사용
          local match
          match=$(find "$base_dir" -type f -name "$expanded" 2>/dev/null \
            | xargs grep -lE -- "$pattern" 2>/dev/null || true)
          if [ -n "$match" ]; then
            found=1
            echo "$match"
          fi
        done
      else
        local match
        match=$(find "$base_dir" -type f -name "$name_part" 2>/dev/null \
          | xargs grep -lE -- "$pattern" 2>/dev/null || true)
        if [ -n "$match" ]; then
          found=1
          echo "$match"
        fi
      fi
    done

    if [ "$found" -eq 1 ]; then
      echo "CONTRACT 위반: $id — $desc (참조: $ref)"
      VIOLATIONS=$((VIOLATIONS + 1))
    fi
  }

  # YAML 라인별 파싱
  local in_rules=0
  local prev_files=()

  while IFS= read -r line || [ -n "$line" ]; do
    # 주석·빈 줄 스킵
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue

    # rules: 섹션 진입
    if [[ "$line" =~ ^rules: ]]; then
      in_rules=1
      continue
    fi

    [ "$in_rules" -eq 0 ] && continue

    # 새 규칙 시작 — 이전 규칙 처리
    if [[ "$line" =~ ^[[:space:]]{2}-[[:space:]]id:[[:space:]]*(.*) ]]; then
      # 이전 규칙 실행
      if [ -n "$current_id" ]; then
        run_rule "$current_id" "$current_desc" "$current_pattern" "$current_ref" "${file_patterns[@]+"${file_patterns[@]}"}"
      fi
      # 새 규칙 초기화
      current_id="${BASH_REMATCH[1]}"
      current_desc=""
      current_pattern=""
      current_ref=""
      current_action="warn"
      in_files=0
      file_patterns=()
      continue
    fi

    # files: 인라인 배열 ["glob1", "glob2"]
    if [[ "$line" =~ ^[[:space:]]{4}files:[[:space:]]*\[(.+)\] ]]; then
      in_files=0
      local inline="${BASH_REMATCH[1]}"
      # 쉼표로 분리, 따옴표 제거
      while IFS= read -r -d ',' item || [ -n "$item" ]; do
        item=$(echo "$item" | sed 's/^[[:space:]]*"//;s/"[[:space:]]*$//')
        [ -n "$item" ] && file_patterns+=("$item")
      done <<< "$inline"
      continue
    fi

    # files: 블록 시작 (멀티라인)
    if [[ "$line" =~ ^[[:space:]]{4}files:[[:space:]]*$ ]]; then
      in_files=1
      continue
    fi

    # files 항목
    if [ "$in_files" -eq 1 ] && [[ "$line" =~ ^[[:space:]]{6}-[[:space:]]\"?([^\"]+)\"?[[:space:]]*$ ]]; then
      file_patterns+=("${BASH_REMATCH[1]}")
      continue
    fi

    # 다른 필드가 나오면 files 블록 종료
    if [[ "$line" =~ ^[[:space:]]{4}[a-z] ]]; then
      in_files=0
    fi

    # description
    if [[ "$line" =~ ^[[:space:]]{4}description:[[:space:]]*\"?(.+)\"?[[:space:]]*$ ]]; then
      current_desc="${BASH_REMATCH[1]}"
      # 따옴표 제거
      current_desc="${current_desc%\"}"
      current_desc="${current_desc#\"}"
      continue
    fi

    # pattern
    if [[ "$line" =~ ^[[:space:]]{4}pattern:[[:space:]]*\"(.+)\"[[:space:]]*$ ]]; then
      current_pattern="${BASH_REMATCH[1]}"
      # YAML 이중 이스케이프 해제: \\\\ → \\, \\\. → \.
      current_pattern="${current_pattern//\\\\/\\}"
      continue
    fi

    # contract_ref
    if [[ "$line" =~ ^[[:space:]]{4}contract_ref:[[:space:]]*\"?(.+)\"?[[:space:]]*$ ]]; then
      current_ref="${BASH_REMATCH[1]}"
      current_ref="${current_ref%\"}"
      current_ref="${current_ref#\"}"
      continue
    fi

    # action
    if [[ "$line" =~ ^[[:space:]]{4}action:[[:space:]]*(.*) ]]; then
      current_action="${BASH_REMATCH[1]}"
      continue
    fi

  done < "$rules_file"

  # 마지막 규칙 처리
  if [ -n "$current_id" ]; then
    run_rule "$current_id" "$current_desc" "$current_pattern" "$current_ref" "${file_patterns[@]+"${file_patterns[@]}"}"
  fi
}

# ast-grep 사용 가능 여부 확인 (있으면 안내, 없으면 regex fallback)
if command -v ast-grep &>/dev/null; then
  echo "check-contract: ast-grep 감지됨 — regex fallback 사용 중 (ast-grep 통합 예정)"
fi

echo "check-contract: 규칙 파일: $RULES_FILE"
echo "check-contract: 검사 경로: $SEARCH_PATH"
echo "---"

parse_and_check "$RULES_FILE" "$SEARCH_PATH"

echo "---"
if [ "$VIOLATIONS" -eq 0 ]; then
  echo "check-contract: 위반 없음."
else
  echo "check-contract: 위반 $VIOLATIONS 건 발견."
fi

# --strict 모드에서만 exit 1
if [ "$STRICT" -eq 1 ] && [ "$VIOLATIONS" -gt 0 ]; then
  exit 1
fi

exit 0
