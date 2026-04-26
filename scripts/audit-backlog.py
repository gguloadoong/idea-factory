#!/usr/bin/env python3
"""audit-backlog.py — v8 백로그 상태 감사 스크립트

백로그 마크다운에 기록된 상태와 실제 GitHub PR/Issue 상태 + 파일 존재 여부를
크로스체크. v8.1 이후 백로그 원본은 공개 레포에서 비공개 로컬로 이전됨 —
이 스크립트는 `IDEA_FACTORY_BACKLOG_PATH` 환경변수로 그 경로를 받는다.

Usage:
  IDEA_FACTORY_BACKLOG_PATH=~/private/v8-backlog.md python3 scripts/audit-backlog.py
  python3 scripts/audit-backlog.py --fix        # backlog 자동 갱신
  python3 scripts/audit-backlog.py --json       # JSON 출력
"""

import json
import os
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
_env_path = os.environ.get("IDEA_FACTORY_BACKLOG_PATH")
BACKLOG = Path(_env_path).expanduser() if _env_path else ROOT / "docs" / "plans" / "v8-backlog.md"

# ── Item registry ────────────────────────────────────────────────
# (id, name, pr_number, issue_number, verification_files)
ITEMS = [
    ("1.1", "Exit-0 audit log", 5, 4, ["templates/hooks/check-audit.sh"]),
    ("1.2", "Write-time secret scanner", 0, 6, ["templates/hooks/check-secret-scan.sh"]),
    ("1.3", "Deny-list extensions", 18, 16, [
        "templates/settings-extensions/web-app.json",
        "templates/settings-extensions/cron-bot.json",
        "templates/settings-extensions/trading.json",
        "templates/settings-extensions/payment.json",
        "scripts/merge-settings.sh",
    ]),
    ("1.4", "Audit post-session reviewer", 0, 0, ["templates/hooks/audit-review.sh"]),
    ("2.1", "docs/research/ directory", 0, 0, ["docs/research/"]),
    ("2.2", "docs/field-reports/ directory", 0, 0, ["docs/field-reports/"]),
    ("2.3", "v8-backlog.md", 0, 0, ["docs/plans/v8-backlog.md"]),
    ("2.4", "Session auto-capture", 14, 15, ["templates/hooks/stop-learning-capture.sh"]),
    ("2.5", "Research artifact template", 0, 6, ["templates/research-report.md.tmpl"]),
    ("3.1", "Loop breaker", 14, 13, ["templates/hooks/check-loop-breaker.sh"]),
    ("3.2", "AST-level CONTRACT", 0, 0, ["templates/contract-rules/example-rules.yml", "scripts/check-contract.sh"]),
    ("3.3", "Zombie resurrection hook", 0, 0, ["templates/hooks/check-zombie-resurrection.sh"]),
    ("3.4", ".protected-files YAML", 0, 0, ["templates/protected-files.yml", "templates/hooks/check-protected-files.sh"]),
    ("4.1", "Decay counter", 14, 13, ["templates/hooks/check-decay-counter.sh"]),
    ("4.2", "Auto-compact loss validation", 0, 0, ["scripts/validate-handoff.sh", "templates/handoff-checklist.md.tmpl"]),
    ("4.3", "Tried-and-failed ledger", 0, 0, ["templates/hooks/check-failed-attempts.sh", "scripts/record-failure.sh"]),
    ("5.1", "Tuning harness", 19, 17, [
        "templates/workflows/tuning-session.md",
        "scripts/tuning-gate.sh",
        "templates/experiments/README.md",
    ]),
    ("5.2", "Cron-bot template", 19, 17, ["templates/cron-bot/CLAUDE.md.tmpl"]),
    ("5.3", "Runtime metrics ratchet", 0, 0, ["templates/scripts/runtime-ratchet.sh", "templates/ratchet.yml.tmpl"]),
    ("5.4", "Copied-code drift detection", 0, 0, [
        "templates/COPIED-FROM.md.tmpl",
        "scripts/check-copy-drift.sh",
    ]),
    ("5.5", "Temporal leakage lint", 0, 0, ["templates/lints/temporal-leakage/patterns.json", "scripts/lint-temporal-leakage.sh"]),
    ("6.1", "Rule-driven gate sizing", 0, 0, ["templates/gate-rules.yml", "scripts/run-gate.sh"]),
    ("6.2", "Numeric-tuning gate preset", 0, 0, ["templates/gate-presets/numeric-tuning.yml"]),
    ("7.1", "Session state persistence", 0, 0, ["templates/hooks/pre-compact-save.sh", "templates/hooks/session-start-restore.sh"]),
    ("7.2", "Cost tracking", 10, 9, ["templates/hooks/stop-cost-summary.sh"]),
    ("7.3", "Config protection", 12, 11, ["templates/hooks/check-config-protection.sh"]),
    ("7.4", "Downstream sync", 21, 20, [
        "scripts/sync-downstream.sh",
        "scripts/sync-lib.py",
        "downstream-registry.json",
        "sync-manifest.json",
    ]),
]

WAVE0_ITEMS = [
    ("W0.1", "SKILL.md path fix", 8, 7, []),
    ("W0.2", "Agent vendoring", 8, 7, [
        "templates/agents/architect.md",
        "templates/agents/code-reviewer.md",
        "templates/agents/critic.md",
        "templates/agents/qa-tester.md",
    ]),
    ("W0.3", "Test infra", 8, 7, ["tests/run-all.sh", "tests/README.md"]),
    ("W0.4", "CI exit-0 invariant", 8, 7, ["tests/invariant-exit-zero.sh", ".github/workflows/ci.yml"]),
    ("W0.5", "Research archive", 8, 7, ["docs/research/2026-04-12-ecc-comparison.md"]),
]

THEMES = {
    "1": "Runtime Safety",
    "2": "Learning Layer",
    "3": "Enforcement",
    "4": "Context & Memory",
    "5": "Domain Patterns",
    "6": "Reviewer Gate",
    "7": "ECC Infrastructure",
}


def gh_state(kind: str, num: int) -> str:
    """Get PR or Issue state via gh CLI."""
    if num == 0:
        return "none"
    try:
        result = subprocess.run(
            ["gh", kind, "view", str(num), "--json", "state", "-q", ".state"],
            capture_output=True, text=True, timeout=10,
        )
        return result.stdout.strip() if result.returncode == 0 else "UNKNOWN"
    except Exception:
        return "UNKNOWN"


def get_backlog_status(item_id: str, content: str) -> str:
    """Extract claimed status from backlog markdown."""
    escaped = re.escape(item_id)

    # Check for ✅ DONE in title
    if re.search(rf"### {escaped}\b.*✅\s*DONE", content):
        return "done"

    # Extract from **상태**: `xxx`
    pattern = rf"### {escaped}\b.*?\*\*상태\*\*:\s*`([^`]+)`"
    m = re.search(pattern, content, re.DOTALL)
    if m:
        status_text = m.group(1).strip()
        first_word = status_text.split()[0].strip("()")
        # Normalize
        if first_word.startswith("done"):
            return "done"
        if first_word.startswith("in-progress"):
            return "in-progress"
        if first_word.startswith("in-design"):
            return "in-design"
        if first_word.startswith("todo"):
            return "todo"
        if first_word.startswith("deferred"):
            return "deferred"
        return first_word
    return "unknown"


def determine_actual(pr_num: int, pr_state: str, files: list[str]) -> str:
    """Determine actual status from PR state + file existence."""
    if pr_state == "MERGED":
        if files:
            all_exist = all((ROOT / f).exists() for f in files)
            return "done" if all_exist else "done-but-files-missing"
        return "done"

    if pr_state == "OPEN":
        return "in-progress"

    if pr_state == "CLOSED":
        return "closed-not-merged"

    # No PR — check files
    if files and all((ROOT / f).exists() for f in files):
        return "done"

    return "todo"


def main():
    mode = "report"
    output_format = "text"
    for arg in sys.argv[1:]:
        if arg == "--fix":
            mode = "fix"
        elif arg == "--json":
            output_format = "json"
        elif arg in ("-h", "--help"):
            print(__doc__)
            return

    if not BACKLOG.exists():
        print()
        print("백로그 파일을 찾을 수 없습니다:")
        print(f"  {BACKLOG}")
        print()
        print("v8.1 이후 백로그 원본은 비공개 로컬 위치로 이전되었습니다.")
        print("아래 환경변수에 비공개 백로그 경로를 지정해 다시 실행하세요:")
        print()
        print("  IDEA_FACTORY_BACKLOG_PATH=~/private/v8-backlog.md \\")
        print("    python3 scripts/audit-backlog.py")
        print()
        sys.exit(0)

    backlog_content = BACKLOG.read_text()

    # Batch fetch PR and Issue states
    all_items = ITEMS + WAVE0_ITEMS
    pr_nums = {it[2] for it in all_items if it[2] != 0}
    issue_nums = {it[3] for it in all_items if it[3] != 0}

    pr_states = {n: gh_state("pr", n) for n in pr_nums}
    issue_states = {n: gh_state("issue", n) for n in issue_nums}

    results = []
    drifts = []

    for item_id, name, pr, issue, files in all_items:
        claimed = get_backlog_status(item_id, backlog_content)
        pr_st = pr_states.get(pr, "none")
        issue_st = issue_states.get(issue, "none")
        actual = determine_actual(pr, pr_st, files)

        is_drift = claimed != actual
        entry = {
            "id": item_id,
            "name": name,
            "claimed": claimed,
            "actual": actual,
            "pr": {"num": pr, "state": pr_st},
            "issue": {"num": issue, "state": issue_st},
            "drift": is_drift,
        }
        results.append(entry)
        if is_drift:
            drifts.append(entry)

    if output_format == "json":
        print(json.dumps(results, indent=2, ensure_ascii=False))
        return

    # ── Text report ──────────────────────────────────────────────
    main_items = [r for r in results if not r["id"].startswith("W")]
    wave0 = [r for r in results if r["id"].startswith("W")]

    done_count = sum(1 for r in main_items if r["actual"] == "done")
    wip_count = sum(1 for r in main_items if r["actual"] == "in-progress")
    todo_count = sum(1 for r in main_items if r["actual"] == "todo")

    print()
    print("═" * 55)
    print("  idea-factory v8 백로그 감사 리포트")
    print(f"  {datetime.now().strftime('%Y-%m-%d %H:%M')}")
    print("═" * 55)
    print()
    print(f"  진행 현황: done={done_count}  in-progress={wip_count}  todo={todo_count}  총={len(main_items)}")
    print(f"  Drift 감지: {len(drifts)} 건")
    print()

    if drifts:
        print("── Drift 상세 " + "─" * 41)
        print()
        print(f"  {'ID':<6} {'항목':<32} {'백로그':<14} {'실제':<18} 근거")
        print(f"  {'─'*6} {'─'*32} {'─'*14} {'─'*18} {'─'*15}")
        for d in drifts:
            pr_info = f"PR#{d['pr']['num']}={d['pr']['state']}" if d["pr"]["num"] else ""
            print(f"  {d['id']:<6} {d['name']:<32} {d['claimed']:<14} {d['actual']:<18} {pr_info}")
        print()

    # Per-theme breakdown
    print("── 테마별 현황 " + "─" * 40)
    print()
    current_theme = ""
    for r in main_items:
        theme_num = r["id"].split(".")[0]
        theme = THEMES.get(theme_num, "?")
        if theme != current_theme:
            print(f"  [{theme_num}] {theme}")
            current_theme = theme

        icons = {
            "done": "[DONE]",
            "in-progress": "[WIP] ",
            "todo": "[TODO]",
            "done-but-files-missing": "[WARN]",
        }
        icon = icons.get(r["actual"], "[????]")
        drift_mark = f"  <- DRIFT (backlog: {r['claimed']})" if r["drift"] else ""
        print(f"    {icon} {r['id']} {r['name']}{drift_mark}")

    print()
    print("  [Wave 0] Safety Foundation")
    for r in wave0:
        print(f"    [DONE] {r['id']} {r['name']}")

    # Open Issues/PRs
    print()
    print("── 열린 Issue/PR " + "─" * 38)
    print()
    has_open = False
    for r in main_items:
        if r["pr"]["num"] and r["pr"]["state"] == "OPEN":
            print(f"  PR #{r['pr']['num']} OPEN — {r['id']} {r['name']}")
            has_open = True
        if r["issue"]["num"] and r["issue"]["state"] == "OPEN":
            print(f"  Issue #{r['issue']['num']} OPEN — {r['id']} {r['name']}")
            has_open = True
    if not has_open:
        print("  (없음)")
    print()

    # ── Fix mode ─────────────────────────────────────────────────
    if mode == "fix" and drifts:
        print("── 자동 갱신 적용 중 " + "─" * 34)
        print()
        content = backlog_content

        for d in drifts:
            if d["actual"] in ("done", "done-but-files-missing") and d["claimed"] not in ("done",):
                item_id = d["id"]
                escaped = re.escape(item_id)

                # Pattern: **상태**: `old_status...`
                pattern = rf"(### {escaped}\b.*?\*\*상태\*\*:\s*`)([^`]+)(`)"

                def replacer(m):
                    return m.group(1) + "done" + m.group(3)

                new_content = re.sub(pattern, replacer, content, flags=re.DOTALL)
                if new_content != content:
                    content = new_content
                    print(f"  {item_id}: {d['claimed']} -> done")
                else:
                    print(f"  {item_id}: 패턴 매치 실패 (수동 수정 필요)")

        # Update summary stats table
        # Recalculate per-theme stats
        theme_stats = {}
        for item_id, name, pr, issue, files in ITEMS:
            theme_num = item_id.split(".")[0]
            if theme_num not in theme_stats:
                theme_stats[theme_num] = {"HIGH": 0, "MED": 0, "LOW": 0, "DONE": 0, "total": 0}

            r = next(r for r in results if r["id"] == item_id)
            actual = r["actual"]
            if actual in ("done", "done-but-files-missing"):
                theme_stats[theme_num]["DONE"] += 1
            theme_stats[theme_num]["total"] += 1

        # Count priorities from backlog text
        for item_id, name, pr, issue, files in ITEMS:
            theme_num = item_id.split(".")[0]
            escaped = re.escape(item_id)
            header_match = re.search(rf"### {escaped}\s+.+?\[(HIGH|MED|LOW)", content)
            if header_match:
                prio = header_match.group(1)
                theme_stats[theme_num][prio] += 1

        # Build new stats table
        new_table_lines = []
        new_table_lines.append("| Theme | HIGH | MED | LOW | DONE | 총 |")
        new_table_lines.append("|---|---|---|---|---|---|")
        total_h = total_m = total_l = total_d = total_t = 0
        for tn in sorted(theme_stats.keys()):
            s = theme_stats[tn]
            theme_name = THEMES.get(tn, "?")
            new_table_lines.append(
                f"| {tn}. {theme_name} | {s['HIGH']} | {s['MED']} | {s['LOW']} | {s['DONE']} | {s['total']} |"
            )
            total_h += s["HIGH"]
            total_m += s["MED"]
            total_l += s["LOW"]
            total_d += s["DONE"]
            total_t += s["total"]
        new_table_lines.append(
            f"| **합계** | **{total_h}** | **{total_m}** | **{total_l}** | **{total_d}** | **{total_t}** |"
        )
        new_table = "\n".join(new_table_lines)

        # Replace old stats table
        old_table_pattern = r"\| Theme \| HIGH \|.*?\| \*\*합계\*\* \|[^\n]+\n"
        content = re.sub(old_table_pattern, new_table + "\n", content, flags=re.DOTALL)

        # Update last-updated date
        content = re.sub(
            r"Last updated: \d{4}-\d{2}-\d{2}[^\n]*",
            f"Last updated: {datetime.now().strftime('%Y-%m-%d')} (audit-backlog.py auto-sync)",
            content,
        )

        BACKLOG.write_text(content)
        print()
        print("  갱신 완료.")

    print("═" * 55)


if __name__ == "__main__":
    main()
