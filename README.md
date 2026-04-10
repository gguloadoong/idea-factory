<div align="center">

# idea-factory

### One idea in. Working MVP out.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Compatible-blueviolet)](https://docs.anthropic.com/en/docs/claude-code)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](http://makeapullrequest.com)

**idea-factory** turns Claude Code into a virtual startup.<br>
You're the CEO — describe what you want in one line, and a team of AI agents builds it.

[Quick Start](#install) · [How It Works](#how-it-works) · [한국어 가이드](docs/ko/README.md)

</div>

---

## What's New in v7.1

v7.1 (2026-04-11) is a hotfix over v7 that removes blocking PreToolUse hooks which were stalling downstream autonomous workflows (see [#2](https://github.com/gguloadoong/idea-factory/issues/2)). `templates/settings.json` now ships with `defaultMode: "bypassPermissions"` and an empty `PreToolUse` — the `deny` list still blocks destructive ops (`rm -rf /`, `sudo *`, `.env*`, credentials, secrets).

v7 (2026-04-04) was the harness engineering overhaul: 11 battle-tested patterns from market-dashboard-v5 — Quality Ratchet, Protected Files, 5-Stage PR Pipeline, 6-Gate Deploy Consensus, CONTRACT FAQ, agent depth guidance, and more. See [HARNESS-GUIDE.md](skills/start-company/HARNESS-GUIDE.md#changelog) for the full changelog.

v6.1 laid the foundation: 4-reviewer gate, isolated worktrees, two-pass evaluation, Playwright MCP, phase handoffs, Codex Gate. Informed by [Anthropic's harness engineering research](https://www.anthropic.com/engineering/harness-design-long-running-apps) (March 2026).

| Feature | What it does |
|---------|-------------|
| **4-Reviewer Gate** | architect + critic + code-reviewer + qa-tester review in parallel (was 3) |
| **Fresh Context Isolation** | Every reviewer runs in an isolated worktree — no self-praise bias |
| **Two-Pass Evaluation** | Pass 1: adversarial defect hunt (mandatory). Pass 2: structured scoring (optional, fresh context). Eliminates "Evaluator Leniency" |
| **Playwright MCP** | qa-tester opens the live app in a real browser, clicks buttons, fills forms — not just code review |
| **Phase Handoff Documents** | MVP, Harden, Ship phases produce handoff docs preserving context across transitions |
| **Codex Gate** | Optional cross-model review via OpenAI Codex CLI for a second opinion on diffs |
| **Safety via deny-list** | `permissions.deny` blocks destructive ops (`rm -rf /`, `sudo *`) and sensitive reads (`.env*`, credentials, secrets). No blocking PreToolUse hooks — autonomous workflows stay zero-friction. |
| **CLAUDE.md 80-Line Limit** | Generated project CLAUDE.md stays under 80 lines (HumanLayer research: compliance drops beyond ~150 instructions) |
| **Fix-Loop Circuit Breaker** | Same failure 3 times = stop and escalate to CEO (no more infinite token-burning loops) |
| **HARNESS-GUIDE.md** | New design document explaining every architectural decision with evidence |

---

## Demo

One command. A complete MVP in under an hour.

```terminal
$ claude
> /start-company 프리랜서 수입 지출 자동 관리 앱

[ANALYZE] analyst + architect analyzing in parallel...
  → Service: CashFreel (캐시프릴)
  → Type: SaaS — Freelancer tax prediction
  → Team: PM + Developer + Designer

[SCAFFOLD] Creating project from templates...
  → CLAUDE.md, agents, hooks, settings ✓
  → git init ✓

[KICKOFF] CEO, 4 quick questions:
  1. Design feel? → Toss style (minimal, big numbers)
  2. MVP scope? → Tax prediction + income/expense tracking
  3. Revenue? → Free first, decide later
  4. Income scope? → Domestic + international

[BUILD] ralph loop running MVP stories...
  ✅ MVP-001: Next.js + Tailwind + shadcn/ui
  ✅ MVP-002: Income registration (KRW + USD + EUR)
  ✅ MVP-003: Expense tracking + auto-categorization
  ✅ MVP-004: Real-time tax dashboard + charts
  ✅ MVP-005: Cash flow report + CSV export

[VALIDATE] 4 independent reviewers (isolated worktrees):
  ✅ architect (opus): no structural blockers for Phase 2
  ✅ critic (opus): no essence drift detected
  ✅ code-reviewer (opus): 0 critical, 2 medium (non-blocking)
  ✅ qa-tester (playwright): all 7 flows pass in real browser

→ MVP complete. Phase 2 ready when you are.
```

**Result:** CashFreel now has a working prototype. Next phase: connect real tax APIs, add authentication, harden security. CEO didn't write a single line of code.

---

## The Problem

Vibe coding is fast, but chaotic. You get code — not a product.

Real startups don't just have developers. They have **process**: a PM who says "no", a designer who researches before drawing, a QA who breaks things on purpose, and a critic who asks "but why?"

**idea-factory** gives you both: the speed of AI + the discipline of a real team.

<table>
<tr>
<td align="center"><b>Tool</b></td>
<td align="center"><b>Approach</b></td>
<td align="center"><b>You need to be</b></td>
</tr>
<tr>
<td>Vibe coding</td>
<td>"Just build it"</td>
<td>A developer</td>
</tr>
<tr>
<td><a href="https://github.com/garrytan/gstack">gstack</a></td>
<td>Engineering team</td>
<td>A developer</td>
</tr>
<tr>
<td><b>idea-factory</b></td>
<td><b>Full startup team</b></td>
<td><b>Just the CEO</b></td>
</tr>
</table>

---

## How It Works

```
You: /start-company a portfolio tracker for busy investors
```

```
  ANALYZE ──────── Two agents dissect your idea in parallel
     │              (market fit, tech stack, team composition)
     ▼
  SCAFFOLD ─────── Project created from templates, not from scratch
     │
     ▼
  KICKOFF ──────── 3-5 plain-language questions — no jargon, just choices
     │
     ▼
  BUILD MVP ────── Mock data first. Core flow only.
     │              Every feature checked: "Does this serve the Why?"
     ▼
  VALIDATE ─────── 4 reviewers in isolated worktrees (defects first):
     │              Architect + Critic + Code-Reviewer + QA (Playwright)
     │              ↳ critical defect? fix and retry. all clear? CEO confirms.
     ▼
  HARDEN ──────── Real APIs, tests, security — only after MVP is validated
     │
     ▼
  SHIP ────────── Deploy + retrospective
```

---

## MVP-First Philosophy

> Most AI tools rush to connect APIs and deploy. We do the opposite.

| Phase | What happens | Real APIs? | Deploy? |
|-------|-------------|:----------:|:-------:|
| **1 — Prototype** | Mock data, core flow, validate the "wow" | No | No |
| **2 — Harden** | Real APIs, error handling, tests, security | Yes | No |
| **3 — Ship** | Deploy after security audit passes | Yes | Yes |

**Why?** Because connecting a payment API before knowing if anyone wants your product is a waste of everyone's time.

---

## Essence Verification

Every feature is checked against your service's **"Why"**:

```
essence.md
├── One-Line Definition: what this is
├── Why This Exists:     the problem it solves
├── Wow Factor:          what makes users go "wow"
├── Differentiator:      what competitors don't do
└── Key Metric:          the one number that matters
```

- After every story: does this serve the Why?
- At every gate: is the codebase drifting from the vision?
- Drift too far → the system flags it and suggests a **pivot**

---

## Install

```bash
# One-liner
curl -fsSL https://raw.githubusercontent.com/gguloadoong/idea-factory/main/install.sh | bash

# Or clone locally
git clone https://github.com/gguloadoong/idea-factory.git
cd idea-factory && bash install.sh
```

### Prerequisites

| Required | Optional |
|----------|----------|
| [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) | [oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode) (for `ralph` autonomous loop) |
| Node.js 18+ | Gemini CLI (external perspective) |
| Git | |

---

## Usage

```
/start-company a portfolio tracking app for busy investors
```

That's it. The system will:
1. Analyze your idea and form a minimum team
2. Set up the project with proper structure
3. Ask you 3-5 simple questions
4. Start building autonomously

### When does it ask you?

| It asks | It doesn't ask |
|---------|---------------|
| Design feel (A/B/C choices) | Tech stack decisions |
| MVP scope | Architecture choices |
| Revenue model | Code review results |
| "Is this the right direction?" | Bug fixes |
| API keys when actually needed | Anything it can decide |

---

## What's Inside

```
idea-factory/
├── skills/start-company/    # The trigger
│   ├── SKILL.md             # v6.1 execution flow
│   └── HARNESS-GUIDE.md     # Design decisions & evidence
├── templates/               # Pre-built, reusable
│   ├── CLAUDE.md.tmpl       # Project constitution
│   ├── settings.json        # Permissions + hooks
│   ├── agents/              # PM, Developer, Designer
│   ├── hooks/               # check-quality, check-careful, check-safety
│   ├── documents/           # PRD, essence, CONTRACT, handoff template
│   └── scripts/             # codex-review-gate.sh (cross-model review)
├── install.sh               # One-command installer
└── docs/ko/                 # Korean documentation
```

### Design Decisions

| Decision | Why |
|----------|-----|
| **Templates, not generation** | Creating 30 files from scratch wastes the context window on boilerplate |
| **ralph as backbone** | Post-condition chaining between skills is unreliable; a state-machine loop isn't |
| **4 isolated reviewers** | Same-session role-play isn't real analysis; worktree-isolated agents with fresh context are |
| **Defects first, scores second** | Scoring alone triggers "Evaluator Leniency" (AI gives 9/10). Defect hunt first forces honesty |
| **Playwright MCP for QA** | Code review alone misses UI bugs; real browser interaction catches what humans catch |
| **essence.md as North Star** | Without it, features drift from the original vision within 2 sprints |
| **CLAUDE.md under 80 lines** | AI compliance drops beyond ~150 instructions; system prompt uses ~50, leaving ~100 for the project |
| **Fix-loop circuit breaker** | Without a cap, agents burn tokens in infinite retry loops on the same error |

---

## Examples

```bash
/start-company a pet health management app
/start-company subscription meal delivery for seniors
/start-company hospital booking and report automation tool
/start-company freelancer income/expense auto-tracker
/start-company AI-powered study planner for college students
```

---

## Inspired By

- [gstack](https://github.com/garrytan/gstack) — Sprint pipeline, meta-skills
- [Citadel](https://github.com/SethGammon/Citadel) — Single entry point routing
- [oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode) — Agent orchestration
- [everything-claude-code](https://github.com/affaan-m/everything-claude-code) — Cross-platform skills

---

## Contributing

PRs welcome! Whether it's new agent templates, better hooks, or translations.

## License

MIT

---

<div align="center">
<sub>Built with Claude Code. For founders who'd rather think about the product than the code.</sub>
</div>
