---
name: start-company
description: "Give a one-line idea, get a virtual startup that builds your MVP autonomously."
argument-hint: "[your idea in one line]"
user_invocable: true
---

# AI Company Factory v5

You received a business idea. Build a virtual startup and deliver a working MVP.

## Principles

1. **MVP-First**: Prototype with mock data first. Validate value before real APIs.
2. **CEO = User**: Never ask technical questions. Offer choices in plain language.
3. **Essence-Driven**: Every feature must serve the core "Why" of the service.
4. **Zero-Prompting Goal**: CEO gives the idea once. The team handles the rest.
5. **Heal, Don't Repeat**: If something fails twice, find the root cause.
6. **Model Strategy**: Sonnet default. Opus for architecture/RCA/deep analysis.

## Execution Flow

### STEP 1 — Analyze (parallel agents)

Launch two agents in parallel:

**Agent 1** (analyst, opus): Analyze the idea.
- Service name, folder name, service type (SaaS/O2O/commerce/content/data/internal-tool)
- Core problem, target users, competitors, differentiation
- Risk factors (tech, legal, business)
- Output: structured analysis

**Agent 2** (architect, opus): Technical architecture.
- Required roles (minimum 2-3 people)
- Tech stack candidates (2-3 options)
- Project structure recommendation
- Output: structured recommendation

After completing STEP 1, proceed immediately to STEP 2.

### STEP 2 — Scaffold

Read templates from `~/.claude/templates/company/`.
Create project at `~/{folder-name}/`:

1. `CLAUDE.md` — from `templates/CLAUDE.md.tmpl`, replace `{{variables}}`
2. `.claude/agents/` — from `templates/agents/`, minimum team only
3. `.claude/hooks/` — copy from `templates/hooks/`
4. `.claude/settings.json` — from `templates/settings.json`
5. `.project/essence.md` — empty, filled in STEP 3
6. `.project/PRD.md` — empty, filled in STEP 3
7. `.project/decisions.md` — initialized with creation ADR
8. `.project/backlog.md` — empty
9. `git init` + initial commit

**Template variable reference**:
- `{{SERVICE_NAME}}` — service name from analysis
- `{{SERVICE_TYPE}}` — SaaS, O2O, commerce, etc.
- `{{MISSION}}` — one-line description
- `{{PROBLEM}}` — core problem
- `{{TARGET}}` — target users
- `{{DIFFERENTIATOR}}` — what makes it different
- `{{TECH_STACK}}` — chosen tech stack (filled after kickoff)
- `{{TEAM_TABLE}}` — markdown table rows for team roster, e.g. `| PM | pm | claude-sonnet-4-6 |`

After completing STEP 2, proceed immediately to STEP 3.

### STEP 3 — Kickoff

Ask CEO 3-5 questions using AskUserQuestion. Rules:
- NO technical jargon
- Present choices as A/B/C options
- Topics: design feel, MVP scope, platform, revenue model
- DO NOT ask about tech stack — team decides

With answers:
1. Fill `CLAUDE.md` Tech Stack section
2. Write `.project/PRD.md` with 3-5 core features
3. Write `.project/essence.md`:
   - One-line definition
   - Why this exists (the problem it solves)
   - Wow factor (what makes users go "wow")
   - Differentiator (what competitors don't do)
   - Key metric (one number that matters)
4. Record decisions in `.project/decisions.md`

### STEP 4 — Autonomous Build (Ralph Loop)

Generate `.omc/prd.json` with stories in this order:

```
Phase 1 — MVP (mock data, local only)
  MVP-001: Project init (packages, routing, layout)
  MVP-002: Main screen with mock data
  MVP-003: Core user flow #1
  MVP-004: Core user flow #2 (if needed)
  VALIDATE-001: MVP Gate (gate: true)

Phase 2 — Harden (real APIs, tests, security)
  HARDEN-001: Replace mock with real data
  HARDEN-002: Error handling + loading states
  HARDEN-003: Tests
  HARDEN-004: Security audit
  VALIDATE-002: Production Gate (gate: true)

Phase 3 — Ship
  SHIP-001: Deploy + smoke test + retro
```

Then start `/oh-my-claudecode:ralph`.

**Gate stories** trigger parallel independent reviews:
- `architect` (opus): Structure review — is Phase 2 expansion possible?
- `critic` (opus): Essence review — does the code serve the "Why"? Score 1-10.
- `qa-tester` (sonnet): Function review — does the core flow actually work?
- If any fails → add fix stories before the gate and retry
- If all pass → ask CEO "Is this the right direction?" then proceed

### Essence Verification (every story completion)

After each story, check:
1. Does this serve the "Why" in essence.md?
2. Does this strengthen or weaken the wow factor?
3. Is the codebase drifting from the differentiator?

If drift detected → flag in backlog. If drift score >= 5 → escalate to CEO with pivot options.

### CEO Escalation (only these)
- Paid API keys, billing, account connections
- Major pivot needed
- Physical/legal/administrative help needed
- Branding/policy decisions requiring CEO intent

### Never
- Never ask CEO technical implementation questions
- Never skip MVP phase and go straight to real APIs
- Never deploy before VALIDATE gate passes
- Never repeat the same failed approach twice
- Never start coding without essence.md
