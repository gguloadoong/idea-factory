#!/usr/bin/env bash
# merge-example.sh — MCP 프리셋을 .claude/settings.json에 병합
#
# Usage:
#   bash templates/mcp/merge-example.sh --preset <supabase|vercel> [--dry-run] [--global]
#
# Options:
#   --preset <name>   병합할 프리셋 이름 (supabase 또는 vercel)
#   --dry-run         실제 파일 변경 없이 결과를 stdout으로 출력
#   --global          프로젝트 settings.json 대신 ~/.claude/settings.json에 병합
#
# Exit codes:
#   0 — 성공
#   1 — 잘못된 인자 또는 파일 없음

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── 인자 파싱 ────────────────────────────────────────────────────
PRESET=""
DRY_RUN=false
GLOBAL=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --preset)   PRESET="${2:-}"; shift 2 ;;
    --dry-run)  DRY_RUN=true; shift ;;
    --global)   GLOBAL=true; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [ -z "$PRESET" ]; then
  echo "Usage: merge-example.sh --preset <supabase|vercel> [--dry-run] [--global]" >&2
  exit 1
fi

PRESET_FILE="$SCRIPT_DIR/${PRESET}.json"
if [ ! -f "$PRESET_FILE" ]; then
  echo "Error: preset not found: $PRESET_FILE" >&2
  echo "Available presets: supabase, vercel" >&2
  exit 1
fi

if [ "$GLOBAL" = true ]; then
  TARGET_FILE="$HOME/.claude/settings.json"
else
  TARGET_FILE="$(pwd)/.claude/settings.json"
fi

# ── 대상 파일이 없으면 빈 베이스 생성 ───────────────────────────
if [ ! -f "$TARGET_FILE" ]; then
  echo '{}' > "$TARGET_FILE"
fi

# ── jq로 mcpServers 항목 병합 ───────────────────────────────────
if ! command -v jq &>/dev/null; then
  echo "Error: jq가 필요합니다. brew install jq 로 설치하세요." >&2
  exit 1
fi

MERGED=$(jq -s \
  '.[0] as $target | .[1].mcpServers as $new |
   $target | .mcpServers = (($target.mcpServers // {}) + $new)' \
  "$TARGET_FILE" "$PRESET_FILE")

if [ "$DRY_RUN" = true ]; then
  echo "# [dry-run] 병합 결과 (파일 변경 없음):"
  echo "$MERGED"
  exit 0
fi

# ── 실제 쓰기 ────────────────────────────────────────────────────
printf '%s\n' "$MERGED" > "$TARGET_FILE"
echo "병합 완료: ${PRESET} → $TARGET_FILE"
