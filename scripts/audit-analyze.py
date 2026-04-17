#!/usr/bin/env python3
"""audit-analyze.py — JSONL 감사 로그 패턴 감지 분석기

idea-factory v8 item 1.4
check-audit.sh 가 기록한 .claude/audit/YYYY-MM-DD.jsonl 파일을
읽어 세 가지 패턴을 감지하고 Markdown 리포트를 출력한다.

감지 패턴:
  1. 반복 실패 (repeated-failure) — 동일 cmd가 세션 내 ≥3회 등장
     NOTE: check-audit.sh 스키마에 exit code 필드가 없음.
     따라서 실패를 직접 판별할 수 없다. 대신 동일 명령 반복 실행을
     "잠재적 실패 재시도"로 간주하여 ≥3회 등장 시 플래그한다.
  2. 빈도 이상 (frequency-anomaly) — 세션 평균 대비 3σ 초과 도구/태그
  3. 보안 민감 패턴 (suspicious-pattern) — 위험 정규식 매칭 cmd

Usage:
  python3 scripts/audit-analyze.py [--dir DIR] [--since TIME] [--all]

옵션:
  --dir DIR      감사 로그 디렉터리 (기본: .claude/audit/ | AUDIT_DIR 환경변수)
  --since TIME   시간 창 (예: 2h, 30m, 1d). 기본: 오늘 로그 전체
  --all          모든 날짜 파일 스캔 (기본: 오늘만)
  --json         Markdown 대신 JSON 출력
  -h, --help     도움말
"""

import json
import math
import os
import re
import sys
from datetime import datetime, timezone, timedelta
from pathlib import Path

# ── 보안 민감 패턴 목록 ──────────────────────────────────────────
SUSPICIOUS_PATTERNS: list[tuple[str, str]] = [
    (r"rm\s+-[a-zA-Z]*r[a-zA-Z]*f|rm\s+-[a-zA-Z]*f[a-zA-Z]*r", "rm -rf (재귀 강제 삭제)"),
    (r"\bsudo\b", "sudo (권한 상승)"),
    (r"curl\s+.*\|\s*(bash|sh)", "curl | bash (원격 코드 실행)"),
    (r"wget\s+.*\|\s*(bash|sh)", "wget | bash (원격 코드 실행)"),
    (r"\.env\b", ".env 파일 접근"),
    (r"git\s+push\s+.*--force", "git force push"),
    (r"git\s+reset\s+.*--hard", "git reset --hard"),
    (r"redis-cli\s+(flushdb|flushall)", "Redis flush (전체 데이터 삭제)"),
    (r"(AKIA[0-9A-Z]{8,}|sk-[a-zA-Z0-9]{20,}|ghp_[a-zA-Z0-9]{20,})", "시크릿 키 패턴"),
    (r"chmod\s+777", "chmod 777 (과도한 권한)"),
    (r">\s*/etc/", "/etc/ 덮어쓰기"),
    (r"dd\s+if=.*of=", "dd 디스크 쓰기"),
]

# ── 반복 실패 임계값 ─────────────────────────────────────────────
REPEAT_THRESHOLD = 3   # 동일 cmd 세션 내 N회 이상 → 플래그
ANOMALY_SIGMA   = 3.0  # 빈도 이상 감지 σ


def parse_since(since_str: str) -> datetime | None:
    """'2h', '30m', '1d' 형식을 파싱해 cutoff datetime(UTC) 반환."""
    if not since_str:
        return None
    m = re.fullmatch(r"(\d+)([smhd])", since_str)
    if not m:
        print(f"audit-analyze: --since 형식 오류: {since_str!r} (예: 2h, 30m, 1d)", file=sys.stderr)
        sys.exit(2)
    n, unit = int(m.group(1)), m.group(2)
    seconds = {"s": 1, "m": 60, "h": 3600, "d": 86400}[unit]
    return datetime.now(timezone.utc) - timedelta(seconds=n * seconds)


def load_events(audit_dir: Path, all_files: bool, cutoff: datetime | None) -> list[dict]:
    """JSONL 파일에서 이벤트를 로드한다."""
    if not audit_dir.is_dir():
        print(f"audit-analyze: 감사 로그 디렉터리가 없습니다: {audit_dir}", file=sys.stderr)
        print("  Claude Code 세션을 한 번 실행하면 자동으로 생성됩니다.", file=sys.stderr)
        sys.exit(0)

    today = datetime.now().strftime("%Y-%m-%d")
    if all_files:
        files = sorted(audit_dir.glob("[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].jsonl"))
    else:
        target = audit_dir / f"{today}.jsonl"
        files = [target] if target.exists() else []

    if not files:
        print(f"audit-analyze: 분석할 로그 파일이 없습니다 ({audit_dir})", file=sys.stderr)
        sys.exit(0)

    events: list[dict] = []
    for f in files:
        try:
            for line in f.read_text(encoding="utf-8").splitlines():
                line = line.strip()
                if not line:
                    continue
                try:
                    ev = json.loads(line)
                except json.JSONDecodeError:
                    continue
                # cutoff 필터
                if cutoff and ev.get("ts"):
                    try:
                        ev_dt = datetime.strptime(ev["ts"], "%Y-%m-%dT%H:%M:%SZ").replace(
                            tzinfo=timezone.utc
                        )
                        if ev_dt < cutoff:
                            continue
                    except ValueError:
                        pass
                events.append(ev)
        except OSError:
            pass

    return events


def detect_repeated_commands(events: list[dict]) -> list[dict]:
    """세션 내 동일 cmd가 REPEAT_THRESHOLD회 이상 등장하는 경우를 감지.

    NOTE: 스키마에 exit code 필드가 없으므로 실패를 직접 확인 불가.
    동일 명령 반복 = 잠재적 재시도(실패 후 재실행)로 간주.
    """
    # {session: {cmd: count}}
    from collections import defaultdict
    session_cmd: dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))
    for ev in events:
        sess = ev.get("session", "unknown")
        cmd = ev.get("cmd", "").strip()
        if cmd:
            session_cmd[sess][cmd] += 1

    findings: list[dict] = []
    for sess, cmds in session_cmd.items():
        for cmd, cnt in cmds.items():
            if cnt >= REPEAT_THRESHOLD:
                findings.append({"session": sess, "cmd": cmd, "count": cnt})

    findings.sort(key=lambda x: x["count"], reverse=True)
    return findings


def detect_frequency_anomalies(events: list[dict]) -> list[dict]:
    """세션별 태그(도구) 빈도가 세션 평균 대비 3σ 초과인 경우 감지."""
    from collections import defaultdict

    # {session: {tag: count}}
    session_tags: dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))
    for ev in events:
        sess = ev.get("session", "unknown")
        tags_raw = ev.get("tags", "").strip()
        if tags_raw:
            for tag in tags_raw.split():
                session_tags[sess][tag] += 1
        else:
            session_tags[sess]["(no-tag)"] += 1

    findings: list[dict] = []
    for sess, tag_counts in session_tags.items():
        counts = list(tag_counts.values())
        if len(counts) < 2:
            continue
        mean = sum(counts) / len(counts)
        variance = sum((c - mean) ** 2 for c in counts) / len(counts)
        sigma = math.sqrt(variance) if variance > 0 else 0
        if sigma == 0:
            continue
        for tag, cnt in tag_counts.items():
            z = (cnt - mean) / sigma
            if z >= ANOMALY_SIGMA:
                findings.append({
                    "session": sess,
                    "tag": tag,
                    "count": cnt,
                    "z_score": round(z, 2),
                    "session_mean": round(mean, 2),
                })

    findings.sort(key=lambda x: x["z_score"], reverse=True)
    return findings


def detect_suspicious_patterns(events: list[dict]) -> list[dict]:
    """cmd 필드에서 보안 민감 패턴을 정규식으로 감지."""
    findings: list[dict] = []
    for ev in events:
        cmd = ev.get("cmd", "")
        if not cmd:
            continue
        for pattern, label in SUSPICIOUS_PATTERNS:
            if re.search(pattern, cmd, re.IGNORECASE):
                findings.append({
                    "ts": ev.get("ts", ""),
                    "session": ev.get("session", "unknown"),
                    "pattern": label,
                    "cmd_preview": cmd[:200],
                })
    return findings


def render_markdown(
    repeated: list[dict],
    anomalies: list[dict],
    suspicious: list[dict],
    event_count: int,
) -> str:
    """분석 결과를 Markdown으로 렌더링한다."""
    now = datetime.now().strftime("%Y-%m-%d %H:%M")
    lines: list[str] = [
        "# 감사 로그 분석 리포트",
        "",
        f"생성: {now} | 분석 이벤트 수: {event_count}",
        "",
        "---",
        "",
    ]

    # 1. 반복 명령
    lines += [
        "## 1. 반복 명령 (Repeated Commands)",
        "",
        f"> 동일 cmd가 세션 내 {REPEAT_THRESHOLD}회 이상 등장 = 잠재적 재시도 신호",
        "> **주의**: 스키마에 exit code 필드가 없어 실패 여부를 직접 확인할 수 없습니다.",
        "",
    ]
    if repeated:
        lines.append("| 세션 | 횟수 | 명령어 (최대 120자) |")
        lines.append("|---|---|---|")
        for f in repeated:
            sess = f["session"][:12]
            cmd_preview = f["cmd"][:120].replace("|", "\\|")
            lines.append(f"| `{sess}` | {f['count']} | `{cmd_preview}` |")
    else:
        lines.append("감지된 반복 명령 없음.")
    lines.append("")

    # 2. 빈도 이상
    lines += [
        "## 2. 빈도 이상 (Frequency Anomalies)",
        "",
        f"> 세션 내 태그 빈도가 평균 대비 {ANOMALY_SIGMA}σ 이상 초과",
        "",
    ]
    if anomalies:
        lines.append("| 세션 | 태그 | 횟수 | Z-Score | 세션 평균 |")
        lines.append("|---|---|---|---|---|")
        for f in anomalies:
            sess = f["session"][:12]
            lines.append(
                f"| `{sess}` | `{f['tag']}` | {f['count']} | {f['z_score']} | {f['session_mean']} |"
            )
    else:
        lines.append("감지된 빈도 이상 없음.")
    lines.append("")

    # 3. 보안 민감 패턴
    lines += [
        "## 3. 보안 민감 패턴 (Suspicious Patterns)",
        "",
        "> 아래 패턴은 의도적 사용일 수도 있습니다. 컨텍스트를 확인하세요.",
        "",
    ]
    if suspicious:
        lines.append("| 시각 | 세션 | 패턴 | 명령어 미리보기 |")
        lines.append("|---|---|---|---|")
        for f in suspicious:
            sess = f["session"][:12]
            cmd_preview = f["cmd_preview"][:100].replace("|", "\\|")
            lines.append(f"| `{f['ts']}` | `{sess}` | {f['pattern']} | `{cmd_preview}` |")
    else:
        lines.append("감지된 보안 민감 패턴 없음.")
    lines.append("")

    lines += [
        "---",
        "",
        "**보안 주의**: 감사 로그에는 민감한 명령어 인자가 포함될 수 있습니다.",
        "이 리포트를 공유할 때 `cmd` 필드의 내용을 마스킹하세요.",
        "",
    ]
    return "\n".join(lines)


def main() -> None:
    audit_dir_str = os.environ.get("AUDIT_DIR", ".claude/audit")
    since_str = ""
    all_files = False
    json_output = False

    args = sys.argv[1:]
    i = 0
    while i < len(args):
        arg = args[i]
        if arg in ("-h", "--help"):
            print(__doc__)
            return
        elif arg == "--dir":
            i += 1
            if i >= len(args):
                print("audit-analyze: --dir 에 값이 필요합니다", file=sys.stderr)
                sys.exit(2)
            audit_dir_str = args[i]
        elif arg == "--since":
            i += 1
            if i >= len(args):
                print("audit-analyze: --since 에 값이 필요합니다 (예: 2h)", file=sys.stderr)
                sys.exit(2)
            since_str = args[i]
        elif arg == "--all":
            all_files = True
        elif arg == "--json":
            json_output = True
        else:
            print(f"audit-analyze: 알 수 없는 옵션: {arg}", file=sys.stderr)
            print("  사용법: python3 scripts/audit-analyze.py --help", file=sys.stderr)
            sys.exit(2)
        i += 1

    audit_dir = Path(audit_dir_str)
    cutoff = parse_since(since_str) if since_str else None

    events = load_events(audit_dir, all_files, cutoff)

    repeated   = detect_repeated_commands(events)
    anomalies  = detect_frequency_anomalies(events)
    suspicious = detect_suspicious_patterns(events)

    if json_output:
        result = {
            "event_count": len(events),
            "repeated_commands": repeated,
            "frequency_anomalies": anomalies,
            "suspicious_patterns": suspicious,
        }
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print(render_markdown(repeated, anomalies, suspicious, len(events)))


if __name__ == "__main__":
    main()
