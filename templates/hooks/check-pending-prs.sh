#!/usr/bin/env bash
# check-pending-prs.sh — SessionStart 훅: 미처리 PR 감지 알림
#
# ─────────────────────────────────────────────────────────────────────
# PURPOSE
# ─────────────────────────────────────────────────────────────────────
# At SessionStart time, check for open PRs via gh CLI.
# If open PRs exist, emit a system-reminder on stdout so Claude is aware.
#
# Output (stdout): system-reminder lines if PRs found, else silent.
# The Claude Code runtime injects stdout of SessionStart hooks as
# <system-reminder> content into the first turn.
#
# ─────────────────────────────────────────────────────────────────────
# CRITICAL INVARIANT: THIS SCRIPT MUST ALWAYS EXIT 0
# ─────────────────────────────────────────────────────────────────────
# SessionStart hooks must never prevent a session from starting.

trap 'exit 0' ERR EXIT

{
  # gh CLI 없으면 조용히 skip (GH_BIN 환경변수로 오버라이드 가능, 테스트용)
  GH="${GH_BIN:-gh}"
  command -v "$GH" >/dev/null 2>&1 || exit 0

  # git remote 없으면 조용히 skip
  git remote get-url origin >/dev/null 2>&1 || exit 0

  # PR 목록 JSON 가져오기 (실패 시 조용히 skip)
  PR_JSON=$("$GH" pr list --state open --json number,title,author,createdAt,labels 2>/dev/null) || exit 0

  # JSON 파싱 + 시간 계산 + 출력 (python3)
  python3 - "$PR_JSON" 2>/dev/null <<'PYEOF'
import sys, json
from datetime import datetime, timezone

raw = sys.argv[1] if len(sys.argv) > 1 else "[]"

try:
    prs = json.loads(raw)
except Exception:
    sys.exit(0)

if not prs:
    sys.exit(0)

def relative_time(created_at_str):
    try:
        # GitHub returns ISO 8601 with Z suffix
        dt = datetime.fromisoformat(created_at_str.replace("Z", "+00:00"))
        now = datetime.now(timezone.utc)
        diff = now - dt
        total_seconds = int(diff.total_seconds())
        if total_seconds < 60:
            return "방금 전"
        elif total_seconds < 3600:
            mins = total_seconds // 60
            return f"{mins}분 전"
        elif total_seconds < 86400:
            hours = total_seconds // 3600
            return f"{hours}시간 전"
        else:
            days = total_seconds // 86400
            return f"{days}일 전"
    except Exception:
        return ""

lines = []
for pr in prs:
    number = pr.get("number", "?")
    title = pr.get("title", "")
    author_obj = pr.get("author") or {}
    author = author_obj.get("login", "unknown") if isinstance(author_obj, dict) else str(author_obj)
    created_at = pr.get("createdAt", "")
    rel = relative_time(created_at)
    time_str = f", {rel}" if rel else ""
    lines.append(f"- #{number} \"{title}\" (by {author}{time_str})")

count = len(prs)
print("<system-reminder>")
print("[PENDING PR REVIEW]")
print()
print(f"미처리 PR이 {count}개 있습니다:")
print()
for line in lines:
    print(line)
print()
print("리뷰가 필요한 PR이 있습니다. 확인하시겠습니까?")
print("</system-reminder>")
PYEOF

} 2>/dev/null

# Explicit exit 0 — the most important line in this script.
exit 0
