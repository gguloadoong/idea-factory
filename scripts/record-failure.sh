#!/usr/bin/env bash
# record-failure.sh — 실패한 시도를 ledger에 기록 (수동 호출용)
#
# idea-factory v8 item 4.3
#
# 사용법:
#   bash scripts/record-failure.sh "시도한 것" "실패 사유" "교훈" ["관련 파일"]
#
# 예시:
#   bash scripts/record-failure.sh \
#     "MOMENTUM_ENTRY_PCT 2.5로 설정" \
#     "과도한 포지션으로 손실 증가" \
#     "entry pct는 1.0 이하로 유지" \
#     ".omc/experiments/tuning.json"

set -euo pipefail

LEDGER="${FAILED_ATTEMPTS_FILE:-.omc/experiments/failed-attempts.jsonl}"

# ── 인자 검증 ────────────────────────────────────────────────────────
if [ $# -lt 3 ]; then
  echo "사용법: $0 \"시도한 것\" \"실패 사유\" \"교훈\" [\"관련 파일\"]" >&2
  exit 1
fi

WHAT="${1}"
REASON="${2}"
LESSON="${3}"
FILE="${4:-}"

# ── 디렉터리 자동 생성 ────────────────────────────────────────────────
LEDGER_DIR="$(dirname "$LEDGER")"
mkdir -p "$LEDGER_DIR"

# ── 타임스탬프 ────────────────────────────────────────────────────────
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || python3 -c "
import datetime
print(datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'))
")

# ── JSONL 기록 (python3으로 올바른 JSON 직렬화 보장) ──────────────────
python3 - "$LEDGER" "$TS" "$WHAT" "$REASON" "$LESSON" "$FILE" <<'PYEOF'
import sys, json

ledger = sys.argv[1]
ts     = sys.argv[2]
what   = sys.argv[3]
reason = sys.argv[4]
lesson = sys.argv[5]
file_  = sys.argv[6] if len(sys.argv) > 6 else ""

entry = {
    "ts": ts,
    "what": what,
    "reason": reason,
    "lesson": lesson,
}
if file_:
    entry["file"] = file_

with open(ledger, "a") as fh:
    fh.write(json.dumps(entry, ensure_ascii=False) + "\n")

print(f"기록 완료: {ledger}")
PYEOF
