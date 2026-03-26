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

[VALIDATE] 3 independent reviewers:
  ✅ architect (opus): structure supports Phase 2
  ✅ critic (opus): essence score 7.5/10
  ✅ qa-tester: all 7 checks passed

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
  VALIDATE ─────── 3 independent reviewers in parallel:
     │              Architect (structure) + Critic (essence) + QA (function)
     │              ↳ fail? fix and retry. pass? CEO confirms direction.
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
├── skills/start-company/    # The trigger — under 140 lines
│   └── SKILL.md
├── templates/               # Pre-built, reusable
│   ├── CLAUDE.md.tmpl       # Project constitution
│   ├── settings.json        # Permissions + hooks
│   ├── agents/              # PM, Developer, Designer
│   ├── hooks/               # Quality gates, safety checks
│   └── documents/           # PRD, essence template
├── install.sh               # One-command installer
└── docs/ko/                 # Korean documentation
```

### Design Decisions

| Decision | Why |
|----------|-----|
| **140-line trigger** | 17K+ token prompts cause Claude to lose context and skip instructions |
| **Templates, not generation** | Creating 30 files from scratch wastes the context window on boilerplate |
| **ralph as backbone** | Post-condition chaining between skills is unreliable; a state-machine loop isn't |
| **Parallel Agent reviews** | Same-session role-play isn't real analysis; separate Agent calls with isolated context are |
| **essence.md as North Star** | Without it, features drift from the original vision within 2 sprints |

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
