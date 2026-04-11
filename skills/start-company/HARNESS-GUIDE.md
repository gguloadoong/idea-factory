# Start-Company Harness Design Guide

> This document explains the design decisions behind the `start-company` skill.
> If you found this on GitHub and want to understand WHY things work this way, read on.

## What is this?

`start-company` is a Claude Code skill that turns a one-line business idea into a working MVP.
You say `/start-company AI investment signal prediction game` and a virtual startup team
analyzes, scaffolds, plans, builds, and ships an application autonomously.

## Harness Engineering Principles

This skill's design is informed by [Anthropic's harness engineering research](https://www.anthropic.com/engineering/harness-design-long-running-apps) (March 2026), which demonstrated that multi-agent architectures inspired by GANs achieve **20x better results** than single-agent approaches in long-running application development.

### Key Findings We Applied

| Anthropic Finding | Our Implementation |
|---|---|
| Separating generator from evaluator prevents self-praise bias | Gate Story uses 4 independent reviewers in isolated worktrees |
| Scoring-based evaluation causes "Evaluator Leniency" | All reviews use defect-detection framing, never numeric scores |
| Context degrades in long sessions | Phase handoff documents preserve state across transitions |
| Playwright-based QA catches UI bugs code review misses | qa-tester uses Playwright MCP to interact with the live app |
| Criteria steering shapes output quality | essence.md acts as the persistent quality compass |
| Simplest solution first, add complexity only when needed | MVP phase uses mock data; real APIs come in Phase 2 |

---

## Design Decision: Two-Pass Evaluation (Defects First, Scores Second)

### The Problem

When you ask an AI to "rate this code 1-10" or "score the design quality", it consistently:
- Gives 8-10/10 regardless of actual quality
- Finds few or zero defects
- Rubber-stamps mediocre work

This is called **Evaluator Leniency** (Anthropic) or **Rubric Gaming** (FreeCodeCamp).

### The Evidence

Verified in two independent contexts:
1. **Anthropic Labs**: "Initial evaluators too readily approved mediocre work" — required multiple rounds of prompt tuning to calibrate
2. **Real-world PM experiment (April 2026)**: When reports were evaluated with a scoring rubric, the AI gave near-perfect scores and found almost no issues. Removing the scoring system caused the same AI to discover significantly more problems.

### BUT: Scoring Is Not Always Bad

Anthropic successfully used scoring in their harness — with 4 criteria (Design Quality,
Originality, Craft, Functionality) weighted and tuned over multiple iterations.

The official `code-review` plugin in Anthropic's marketplace also uses scoring effectively:
it runs **5 parallel agents that find defects FIRST**, then a separate agent scores each
defect's confidence 0-100, filtering out anything below 80. This is the two-pass pattern.

**The key difference:**
- Scoring ALONE → Evaluator Leniency (AI gives 9/10 and moves on)
- Defects FIRST → Scores SECOND → works well (AI can't ignore defects it already listed)

### The Solution: Two-Pass Gate Review

```
PASS 1 — Defect Hunt (mandatory, adversarial framing):
  "You are a hostile tech lead. Find every structural problem."
  Output: concrete defect list

PASS 2 — Structured Score (optional, fresh context):
  Score on 4 axes: Functionality / Essence / Code Quality / UX
  Each 1-10, hard threshold: any axis < 6 = auto-fail
  BUT: the scorer has already seen the defect list from Pass 1
```

```
WRONG: "Rate this 1-10" (scoring without prior defect detection)
RIGHT: "Find every flaw" → then → "Now score, knowing these flaws exist"
```

### Related Concept: Rhetorical Questions

From [FreeCodeCamp's GAN architecture guide](https://www.freecodecamp.org/news/how-to-apply-gan-architecture-to-multi-agent-code-generation/):

Instead of direct instructions ("Fix line 45"), use questions that activate reasoning:
- "What HTTP status should invalid tokens receive?"
- "Are you following the same pattern as other middleware?"

This produces deeper analysis than mechanical fixes.

---

## Design Decision: Fresh Context Isolation (Worktrees)

### The Problem

When the same AI session builds code AND reviews it, the reviewer inherits all the
reasoning and justifications from the builder. It literally cannot see the flaws because
it remembers why each decision "made sense at the time."

Anthropic's core finding: "Models tend to praise their own work regardless of quality."

### The Solution

Every Gate reviewer runs with `isolation: "worktree"`:
- A fresh copy of the project is created
- The reviewer has ZERO knowledge of the builder's reasoning
- It sees only the output, never the process
- This forces genuine evaluation instead of self-congratulation

This maps directly to Anthropic's GAN-inspired Generator/Evaluator separation.

---

## Design Decision: Playwright MCP for QA

### The Problem

Code-level review can verify that functions exist and tests pass. But it cannot verify:
- A button is visible and clickable on screen
- Navigation flows feel intuitive
- Data displays correctly in the actual UI
- Mobile layouts don't break

Anthropic: "I gave the evaluator the Playwright MCP, which let it interact with the live
page directly before scoring."

### The Solution

The `qa-tester` gate reviewer is equipped with Playwright MCP and instructed to:
1. Start the application if not running
2. Open it in a browser
3. Click every button, fill every form
4. Document: what was done, what was expected, what happened
5. Take screenshots as evidence

This catches the gap between "code looks correct" and "product actually works."

---

## Design Decision: Phase Handoff Documents

### The Problem

Long-running AI sessions suffer from "context degradation" — the AI gradually loses
coherence on what was decided, what works, and what doesn't. When transitioning between
phases (MVP → Harden → Ship), critical knowledge is lost.

Anthropic tested two strategies:
- **Context Reset**: Clear everything and start fresh with a summary
- **Compaction**: Summarize in-place and keep going

### The Solution

At each phase transition, a structured handoff document is generated:
- `handoff-mvp.md`: What works, what doesn't, what was decided, what the gate reviewers found
- `handoff-harden.md`: Same for Harden → Ship transition

The next phase reads this document FIRST, ensuring no knowledge loss. This is the
"Context Reset" strategy with structured information transfer.

---

## Design Decision: Runtime Safety via deny-list (v7.1 revision)

### The Problem

CLAUDE.md rules are "suggestions" — the AI reads them but can still violate them.
A rule saying "never force push" doesn't prevent force push; it only makes it less likely.

### What we tried in v7, and why it broke

v7 shipped a `check-safety.sh` PreToolUse Bash hook (and a sibling `check-careful.sh`)
that intercepted **every** Bash command and blocked 8 dangerous categories (S01-S08:
`sudo`, `.env` in git, `--force` push, `--hard` reset, `--no-verify`, direct push to
main, certificate reads, `rm -rf` on root/home/project).

It was the right instinct and the wrong mechanism. Because blocking PreToolUse hooks
halt the loop mid-iteration, they forced user approval on routine benign commands in
downstream projects. Autopilot and Ralph — the loop-based workflows this repo was
built to enable — stopped working. See [#2](https://github.com/gguloadoong/idea-factory/issues/2)
for the regression report. Lesson: **blocking PreToolUse hooks are architecturally
incompatible with long-running autonomous loops**. Any safety mechanism added to this
template must be exit-0 (observe and log, never halt).

### The v7.1 solution: deny-list floor + bypass mode

`templates/settings.json` ships two coupled mechanisms:

1. **`permissions.defaultMode: "bypassPermissions"`** — routine commands flow through
   without confirmation, preserving loop velocity.
2. **`permissions.deny`** — a narrow floor that the harness refuses to cross, covering
   the catastrophes no autonomous loop should ever need:
   - `Bash(rm -rf /)`, `Bash(rm -rf ~)` — catastrophic deletion
   - `Bash(sudo *)` — privilege escalation
   - `Read(.env*)`, `Read(**/credentials*)`, `Read(**/*secret*)` — secret exfiltration

The narrower deny-list is intentional: it captures the non-recoverable mistakes while
leaving the long tail of "risky but sometimes legitimate" ops (force push, `--hard`
reset, etc.) to CLAUDE.md rules and code review. Those latter cases are recoverable via
git reflog / PR revert; the deny-list targets only the strictly unrecoverable.

### v8.1.1: exit-0 audit log (landed, 2026-04-11)

The logging-only complement to the deny-list — first promised as "out of scope for
v7.1", now shipped as v8 backlog item 1.1.

`templates/hooks/check-audit.sh` runs on every Bash command via PreToolUse matcher.
Its design invariant is **"must always exit 0"**: `trap 'exit 0' ERR EXIT`, every
external call has a fallback, explicit `exit 0` at the bottom. Cannot cause the v7
regression because it has no code path that returns non-zero.

What it does:
- Append `{ts, session, matcher, tags, cmd}` to `.claude/audit/YYYY-MM-DD.jsonl`
- Tag suspicious patterns (label only, not block): `deploy` (vercel --prod, env add/rm),
  `redis-flush` (FLUSHDB/FLUSHALL), `npm-install`, `git-destructive` (force push,
  --hard reset), `rm-rf`
- Stay silent on all failures — a failed audit log is preferable to a stalled loop

What it is NOT:
- Not a replacement for `permissions.deny`. Things that must never happen
  (rm -rf /, sudo, secret reads) still live there.
- Not a blocker. An agent running `vercel --prod` gets tagged `CAREFUL deploy`
  but the command still runs. Enforcement is the deny-list's job.

Downstream projects that care about post-session review (trading bots, payment
services, deploy-sensitive repos) can add `.claude/audit/` to `.gitignore` and
grep the JSONL files when a session misbehaves. A future item (v8 1.4) adds a
post-session auditor agent to surface suspicious sequences automatically.

Complementary pattern: `check-careful.sh` is retained in `templates/hooks/` for
possible future use as a more specialized logging variant. It is currently
unwired — the v8.1.1 `check-audit.sh` is the sole PreToolUse Bash hook.

---

## Architecture Overview

```
/start-company "your idea"
     │
     ├─ STEP 1: Analyze (parallel)
     │   ├─ analyst (opus): business analysis
     │   └─ architect (opus): technical architecture
     │
     ├─ STEP 2: Scaffold
     │   └─ Creates project from templates/company/
     │       ├─ CLAUDE.md (project rules)
     │       ├─ agents/ (team definitions, 50+ lines each)
     │       ├─ hooks/ (check-quality + check-claudemd-size — see v7.1 Design Decision)
     │       ├─ scripts/ (create-pr, pre-deploy-consensus, run-architect, etc.)
     │       ├─ .githooks/ (pre-push stale review warning)
     │       ├─ .project/ (essence, PRD, decisions, backlog, quality-baseline)
     │       └─ .github/ (CI, labels, CodeRabbit, token-health)
     │
     ├─ STEP 3: Kickoff
     │   └─ Ask CEO 3-5 plain-language questions
     │       (NO technical jargon, A/B/C choices only)
     │
     └─ STEP 4: Autonomous Build (Ralph Loop)
         │
         ├─ Phase 1: MVP (mock data)
         │   ├─ MVP-001 → MVP-004: core features
         │   ├─ VALIDATE-001: Gate ← 4 isolated reviewers
         │   │   ├─ architect (worktree): structural defects
         │   │   ├─ critic (worktree): essence drift
         │   │   ├─ code-reviewer (worktree): code quality
         │   │   └─ qa-tester (worktree + Playwright): functional defects
         │   └─ HANDOFF-MVP: write phase transition document
         │       + populate .protected-files with core business logic
         │
         ├─ Phase 2: Harden (real APIs, tests, security)
         │   ├─ reads handoff-mvp.md first
         │   ├─ HARDEN-001 → HARDEN-006
         │   │   (includes .protected-files + quality-baseline.md generation)
         │   ├─ VALIDATE-002: Gate ← 4 isolated reviewers
         │   └─ HANDOFF-HARDEN: write phase transition document
         │
         └─ Phase 3: Ship
             ├─ reads handoff-harden.md first
             ├─ SHIP-001: GitHub repo + branch protection
             ├─ SHIP-002: 5-stage PR pipeline (create-pr.sh)
             ├─ SHIP-003: Deploy with 6-gate consensus
             ├─ SHIP-004: Git hooks setup
             └─ SHIP-005: Final doc sync
```

---

## Design Decision: Quality Ratchet

### The Problem

In long-running projects, quality degrades over time. A feature that worked perfectly in Phase 5
breaks silently in Phase 8 because a dependency changed. Without explicit tracking, regressions
accumulate until the product is unreliable.

### The Evidence

market-dashboard-v5 tracked quality across 13 phases. The ratchet rule ("quality only goes UP")
prevented 4 regressions that would have shipped to production. Each time, the baseline file
flagged a metric decrease (bundle size, API response time, test count) before the PR merged.

### The Solution

After Phase 2 (Harden), generate `.project/quality-baseline.md` from the template. This file
records concrete metrics: build errors (must be 0), test count (must not decrease), bundle size
(must not increase beyond threshold), API fallback chain depth, UI states coverage.

Every PR is checked against the baseline. If any metric regresses, the PR is blocked until either
the regression is fixed or the CEO explicitly approves an exception (with documented reason).

---

## Design Decision: Protected Files (Architect Review Enforcement)

### The Problem

Core business logic files (algorithms, scoring engines, data pipelines) are the most dangerous
to change. A one-line tweak to a threshold constant can break the entire product. Yet these files
look like "simple changes" and often skip review.

### The Solution

After Phase 1, the team identifies critical files and writes them to `.protected-files`.
When any listed file appears in a diff:

1. `run-architect.sh` runs a Claude Opus architect review, saving an artifact with a VERDICT
   and the current commit hash
2. `create-pr.sh` (Stage 1.5) verifies the artifact exists, is for the current commit, and
   has VERDICT: PASS (not BLOCK or missing)
3. If any check fails, the PR is blocked

The commit hash freshness check is critical — it prevents reusing a stale "PASS" from a
previous commit when the code has changed since the review.

---

## Design Decision: 5-Stage PR Pipeline

### The Problem

Manual PR creation skips quality gates. Developers forget to run reviews, miss issue linking,
and merge without waiting for bot feedback.

### The Solution

`create-pr.sh` enforces a 5-stage pipeline that cannot be bypassed:

1. **Build** — `npm run build` must pass (catches compile errors)
2. **Code-reviewer** — artifact must exist with matching commit hash (catches logic bugs)
3. **Codex Gate** — cross-model review if CLI available (catches blind spots)
4. **PR Creation** — auto-links issues from branch name, blocks feat:/fix: without issue number
5. **Bot Polling** — waits for bot reviews to arrive (configurable timeout)

Each stage is a hard gate — failure at any stage stops the pipeline.

---

## Design Decision: 6-Gate Deploy Consensus

### The Problem

"Ship it" pressure leads to deploys without proper verification. A single person's judgment
is insufficient — they might miss an open P0 issue or an unreviewed algorithm change.

### The Solution

`pre-deploy-consensus.sh` runs 6 independent gates before allowing deploy:

1. Build passes (automated)
2. No P0/P1 open issues (automated via GitHub API)
3. PM review — intent matches implementation (automated via claude CLI with nonce-based
   prompt injection prevention)
4. QA approval — quality-baseline.md exists and is current (automated)
5. Dev approval — protected files have architect review (automated)
6. Final sign-off — deploy conditions met (automated)

The nonce system prevents prompt injection: each run generates a random token that the PM
reviewer must include in its verdict. Since the nonce is created at runtime, it cannot be
pre-embedded in commit messages or code comments to manipulate the reviewer.

---

## Design Decision: Session Continuity

### The Problem

Long AI sessions lose track of what was decided, what works, and what the current state is.
Phase transitions are especially risky — critical context is lost between sessions.

### The Solution

Multiple reinforcing mechanisms:
- **Phase handoff documents**: structured state transfer at each transition
- **quality-baseline.md**: concrete metrics that survive context resets
- **Checkpoint auto-save**: every 10 stories or ~2 hours
- **CONTRACT.md**: per-feature truth source with permanent deletion tracking
- **Session Start checklist in CLAUDE.md**: 7 files read in order to restore context

---

## For Non-Developers (PM/PO)

This skill is designed for non-technical CEOs/PMs. Key principles:

1. **You never need to answer technical questions** — the AI team decides tech stack, architecture, and implementation details
2. **Questions come as A/B/C choices** — "Bright and friendly feel?" vs "Professional and clean?"
3. **essence.md is your compass** — one document that defines WHY this product exists; every feature is checked against it
4. **Gate reviews protect you** — 4 independent AI reviewers catch problems before they compound
5. **Phase separation saves money** — fake data first (cheap, fast), real data later (expensive, slow)

---

## References

- [Harness Design for Long-Running Apps](https://www.anthropic.com/engineering/harness-design-long-running-apps) — Anthropic Engineering Blog (2026.03.24)
- [Skill Issue: Harness Engineering for Coding Agents](https://www.humanlayer.dev/blog/skill-issue-harness-engineering-for-coding-agents) — HumanLayer
- [How to Apply GAN Architecture to Multi-Agent Code Generation](https://www.freecodecamp.org/news/how-to-apply-gan-architecture-to-multi-agent-code-generation/) — FreeCodeCamp
- [Claude Code Harness](https://github.com/Chachamaru127/claude-code-harness) — Chachamaru127
- [The GAN-Style Agent Loop](https://www.epsilla.com/blogs/anthropic-harness-engineering-multi-agent-gan-architecture) — Epsilla

## Changelog

- **v7.1 (2026-04-11)**: PreToolUse 훅 회귀 수정 (#2, #3)
  - v7의 `check-careful.sh` + `check-safety.sh` (Bash) + `check-gate-isolation.sh` (Agent) PreToolUse 훅이 다운스트림 프로젝트에서 모든 Bash 명령마다 승인 프롬프트를 유발, 자율 워크플로우 마비
  - `templates/settings.json`: `PreToolUse: []` 로 비움, `permissions.allow` 화이트리스트 제거 후 `defaultMode: "bypassPermissions"` 로 전환
  - `permissions.deny` 는 유지 (`rm -rf /`, `sudo *`, `.env*`, credentials, secrets)
  - `PostToolUse` (CLAUDE.md 크기 체크) 는 유지
  - 교훈: 자율 실행 레포의 PreToolUse 훅은 **exit 0 로깅 전용**이어야 함. Blocking 훅은 근본적으로 autopilot/ralph 워크플로우와 양립 불가.
- **v7 (2026-04-04)**: 11 battle-tested patterns from market-dashboard-v5 (13 phases, 200+ PRs)
  - Quality Ratchet: `.project/quality-baseline.md` — metrics only go up, never down
  - Protected Files: `.protected-files` + `run-architect.sh` — core logic changes require opus review
  - 5-Stage PR Pipeline: `create-pr.sh` — build + code-reviewer + Codex gate + auto issue linking + bot polling
  - 6-Gate Deploy Consensus: `pre-deploy-consensus.sh` — build, P0/P1, PM, QA, dev, final sign-off
  - Nonce-based prompt injection prevention in PM review gate
  - Review Summary: `review-summary.sh` — auto-post combined review results to PR
  - Doc Auto-Update: `update-project-docs.sh` — CONTRACT.md, decisions.md, README sync on PR
  - Git Hooks: `.githooks/pre-push` — stale review warning (soft gate)
  - Token Health: `.github/workflows/token-health.yml` — weekly deploy token check
  - CONTRACT.md FAQ pattern: "Why was X removed?" prevents zombie component resurrection
  - Agent depth guidance: 50+ lines per agent with career anchors and collaboration rules
  - New stories: HARDEN-005/006, SHIP-003/004/005 for hardened ship pipeline
- **v6.1 (2026-04-02)**: Community research + real project integration
  - Gate expanded to 4 reviewers: added `code-reviewer` (global Opus agent with 2-stage review)
  - Cross-model review: Codex Gate integration (from market-dashboard-v5's proven pipeline)
  - Scoring policy corrected: "no scoring" → "defects FIRST, scoring SECOND (two-pass)"
    (Anthropic used scoring successfully with separated evaluators; scoring is not inherently bad)
  - PR pipeline: SHIP-002 now sets up `npm run pr` chain (build → code-reviewer → Codex gate → PR → bot review)
  - `codex-review-gate.sh` added to templates (copied from production v5 project)
  - agnix linting: fixed YAML tools format, hook timeouts, $ARGUMENTS reference
  - New rules: CLAUDE.md 80-line limit, fix-loop 3-attempt circuit breaker, Ghost Bug awareness
  - References updated: HumanLayer, FreeCodeCamp, ARIS, awesome-claude-code, Reddit community patterns
- **v6 (2026-04-02)**: Harness engineering overhaul
  - Gate reviews: scoring → defect-detection framing (Evaluator Leniency fix)
  - Gate reviewers: same context → isolated worktrees (Fresh Context)
  - qa-tester: code-only → Playwright MCP browser testing
  - Phase transitions: implicit → structured handoff documents
  - Safety: basic dangerous command check → 8-rule runtime guardrails
  - Essence verification: numeric drift score → adversarial questions
  - PRD template: removed "score >= 7/10" success criteria
- **v5 (2026-03)**: MVP-First redesign, Ralph state machine, template-based scaffolding
