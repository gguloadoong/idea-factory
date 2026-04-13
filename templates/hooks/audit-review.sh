#!/usr/bin/env bash
# audit-review.sh — Post-session suspicious pattern detector (Stop hook)
#
# idea-factory v8 item 1.4 (docs/plans/v8-backlog.md Theme 1)
#
# ─────────────────────────────────────────────────────────────────────
# PURPOSE
# ─────────────────────────────────────────────────────────────────────
# At session Stop time, read today's .claude/audit/YYYY-MM-DD.jsonl
# files and detect suspicious command sequences via python3. Findings
# are written to .claude/audit/review-YYYY-MM-DD.jsonl and a summary
# is emitted to stdout only when suspicious patterns are found
# (noise-minimizing: silent on clean sessions).
#
# Detected patterns:
#   1. deploy tag immediately after git-destructive (force push → deploy)
#   2. rm-rf tag appears 3+ times in the same session
#   3. redis-flush followed by any other CAREFUL tag
#   4. 10+ total CAREFUL-tagged commands in the session
#   5. npm-install immediately followed by deploy
#
# ─────────────────────────────────────────────────────────────────────
# CRITICAL INVARIANT: THIS SCRIPT MUST ALWAYS EXIT 0
# ─────────────────────────────────────────────────────────────────────
# Stop hooks must never block session completion. Any failure (missing
# audit dir, malformed JSONL, python3 crash) is silently swallowed.
# Enforced by: trap 'exit 0' ERR EXIT + || true guards + explicit exit 0.

trap 'exit 0' ERR EXIT

{
  # ── Configuration ──────────────────────────────────────────────
  AUDIT_DIR="${CLAUDE_AUDIT_DIR:-.claude/audit}"

  # Date helpers with fallbacks
  TODAY=$(date +%Y-%m-%d 2>/dev/null)
  [ -z "$TODAY" ] && TODAY="unknown-date"

  NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
  [ -z "$NOW" ] && NOW="unknown-time"

  # No audit directory → nothing to review
  if [ ! -d "$AUDIT_DIR" ] 2>/dev/null; then
    exit 0
  fi

  # Collect today's audit JSONL files (main log only, not review or cost files)
  AUDIT_FILE="$AUDIT_DIR/$TODAY.jsonl"
  if [ ! -f "$AUDIT_FILE" ] 2>/dev/null; then
    exit 0
  fi

  REVIEW_FILE="$AUDIT_DIR/review-$TODAY.jsonl"

  # ── Read Stop hook payload from stdin ──────────────────────────
  PAYLOAD=""
  if [ ! -t 0 ]; then
    PAYLOAD=$(cat 2>/dev/null || echo '')
  fi
  [ -z "$PAYLOAD" ] && PAYLOAD='{}'

  # ── Run pattern detection in a single python3 call ─────────────
  # All JSON parsing, sequence analysis, and output encoding done in
  # python3 to avoid shell injection and ensure valid JSONL output.
  RESULT=$(python3 - "$AUDIT_FILE" "$REVIEW_FILE" "$NOW" <<'PYEOF' 2>/dev/null
import sys
import json

audit_file = sys.argv[1] if len(sys.argv) > 1 else ""
review_file = sys.argv[2] if len(sys.argv) > 2 else ""
now = sys.argv[3] if len(sys.argv) > 3 else "unknown-time"

CAREFUL_TAGS = {"deploy", "redis-flush", "npm-install", "git-destructive", "rm-rf"}

def load_entries(path):
    entries = []
    try:
        with open(path) as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    e = json.loads(line)
                    if isinstance(e, dict):
                        entries.append(e)
                except Exception:
                    continue
    except Exception:
        pass
    return entries

def get_tags(entry):
    raw = entry.get("tags", "")
    if not isinstance(raw, str):
        return set()
    return set(t.strip() for t in raw.split() if t.strip())

def detect_patterns(entries):
    findings = []

    # Group entries by session
    sessions = {}
    for e in entries:
        sid = e.get("session", "unknown")
        if not isinstance(sid, str):
            sid = str(sid)
        sessions.setdefault(sid, []).append(e)

    for sid, evts in sessions.items():
        # Build tag sequence (entries that have at least one CAREFUL tag)
        tag_seq = []
        for e in evts:
            tags = get_tags(e)
            careful = tags & CAREFUL_TAGS
            if careful:
                tag_seq.append((careful, e.get("ts", ""), e.get("cmd", "")))

        # Pattern 1: git-destructive immediately before deploy
        for i in range(len(tag_seq) - 1):
            if "git-destructive" in tag_seq[i][0] and "deploy" in tag_seq[i + 1][0]:
                findings.append({
                    "pattern": "git-destructive-before-deploy",
                    "session": sid,
                    "severity": "high",
                    "detail": "git-destructive at {} followed immediately by deploy at {}".format(
                        tag_seq[i][1], tag_seq[i + 1][1]
                    ),
                    "cmd_a": tag_seq[i][2][:200],
                    "cmd_b": tag_seq[i + 1][2][:200],
                })

        # Pattern 2: rm-rf 3+ times in same session
        rmrf_count = sum(1 for t, _, _ in tag_seq if "rm-rf" in t)
        if rmrf_count >= 3:
            findings.append({
                "pattern": "rm-rf-repeated",
                "session": sid,
                "severity": "medium",
                "detail": "rm-rf tag appeared {} times in session".format(rmrf_count),
                "count": rmrf_count,
            })

        # Pattern 3: redis-flush followed by any other CAREFUL tag
        for i in range(len(tag_seq) - 1):
            if "redis-flush" in tag_seq[i][0]:
                next_tags = tag_seq[i + 1][0]
                other = next_tags - {"redis-flush"}
                if other:
                    findings.append({
                        "pattern": "redis-flush-followed-by-dangerous",
                        "session": sid,
                        "severity": "medium",
                        "detail": "redis-flush at {} followed by {} at {}".format(
                            tag_seq[i][1], sorted(other), tag_seq[i + 1][1]
                        ),
                        "next_tags": sorted(other),
                    })

        # Pattern 4: 10+ total CAREFUL-tagged commands in session
        total_careful = len(tag_seq)
        if total_careful >= 10:
            findings.append({
                "pattern": "excessive-careful-commands",
                "session": sid,
                "severity": "low",
                "detail": "{} CAREFUL-tagged commands in single session (threshold: 10)".format(
                    total_careful
                ),
                "count": total_careful,
            })

        # Pattern 5: npm-install immediately followed by deploy
        for i in range(len(tag_seq) - 1):
            if "npm-install" in tag_seq[i][0] and "deploy" in tag_seq[i + 1][0]:
                findings.append({
                    "pattern": "npm-install-then-deploy",
                    "session": sid,
                    "severity": "medium",
                    "detail": "npm-install at {} followed immediately by deploy at {}".format(
                        tag_seq[i][1], tag_seq[i + 1][1]
                    ),
                    "cmd_a": tag_seq[i][2][:200],
                    "cmd_b": tag_seq[i + 1][2][:200],
                })

    return findings

entries = load_entries(audit_file)
findings = detect_patterns(entries)

if not findings:
    # No suspicious patterns — stay silent
    sys.exit(0)

# Write findings to review file
try:
    review_entry = {
        "ts": now,
        "audit_file": audit_file,
        "finding_count": len(findings),
        "findings": findings,
    }
    with open(review_file, "a") as fh:
        fh.write(json.dumps(review_entry, ensure_ascii=True) + "\n")
except Exception:
    pass

# Emit summary to stdout for system-reminder display
print("세션 감사 리뷰: {}건 의심 패턴 발견".format(len(findings)))
for f in findings:
    print("  [{}] {} — {}".format(
        f.get("severity", "?").upper(),
        f.get("pattern", "unknown"),
        f.get("detail", "")[:120],
    ))
print("상세 내용: {}".format(review_file))
PYEOF
  )

  # Emit result if non-empty
  if [ -n "$RESULT" ]; then
    printf '%s\n' "$RESULT"
  fi

} 2>/dev/null

# Always exit 0 — the most important line.
exit 0
