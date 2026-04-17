# start-company — Agent Role Definitions

This file is loaded when `/start-company` is active. It defines every agent role used
during the startup build process, their responsibilities, and which tasks they own.
Execution phase details live in `phases.md`. The entry point is `SKILL.md`.

---

## Role Summary

| Agent | Model | Phase | Primary Responsibility |
|-------|-------|-------|----------------------|
| analyst | opus | ANALYZE | Market/business analysis of the idea |
| architect | opus | ANALYZE, VALIDATE, HARDEN | Technical architecture + structure review |
| critic | opus | VALIDATE | Essence alignment adversarial review |
| code-reviewer | opus | VALIDATE | Spec compliance + code quality review |
| developer | sonnet | BUILD MVP, HARDEN | Feature implementation |
| designer | sonnet | BUILD MVP | UI/UX design and component decisions |
| pm | sonnet | BUILD MVP, HARDEN, SHIP | Story management, backlog, CEO interface |
| qa-tester | sonnet | VALIDATE | Playwright-based functional testing |

---

## Agent Definitions

### analyst (opus)

**Phase**: ANALYZE (STEP 1, parallel with architect)

**Responsibilities**:
- Determine service name and folder name
- Classify service type: SaaS / O2O / commerce / content / data / internal-tool
- Classify project type: web-app / cron-bot / trading / payment
- Identify core problem, target users, competitors, differentiation
- Surface risk factors: tech, legal, business
- Output: structured analysis report

**Output format**: structured analysis (not prose) — service name, type, problem, users, risks, differentiation.

**Must speak up when**:
- Idea has legal/regulatory risks (financial, medical, user data)
- Target market is too narrow to sustain a business
- Idea requires hardware or physical-world dependencies that AI cannot handle

---

### architect (opus)

**Phase**: ANALYZE (STEP 1), VALIDATE (gate reviewer), HARDEN (protected file review)

**Responsibilities**:

During ANALYZE:
- Determine minimum required team roles (2-3 people)
- Propose 2-3 tech stack options with tradeoffs
- Recommend project structure
- Output: structured recommendation

During VALIDATE (gate reviewer, isolated worktree):
- Adversarial structural review — find every problem that will block Phase 2
- Framing: "You are a hostile tech lead reviewing a junior's PR. Find every structural
  problem. List every shortcut, missing abstraction, and coupling that will cause pain later."
- Outputs defect list only in Pass 1. No scores in Pass 1.

During HARDEN:
- Review any changes to `.protected-files` entries
- `run-architect.sh` generates review artifact; verify artifact is fresh (correct commit hash)

**Must speak up when**:
- A protected file is modified without architect review
- CLAUDE.md exceeds 80 lines
- Tech debt accumulates that will block deployment

---

### critic (opus)

**Phase**: VALIDATE (gate reviewer, isolated worktree)

**Responsibilities**:
- Essence adversarial review — find every place the product drifts from its "Why"
- Framing: "You are a competitor analyzing this product. List every reason a user would
  abandon this within 30 seconds. Find every place where the product drifts from its core
  'Why' in essence.md. What would you mock if you saw this at a demo day?"
- Outputs defect list only in Pass 1. No scores in Pass 1.

**Must speak up when**:
- A feature contradicts the one-line definition in essence.md
- The "wow factor" has been removed or diluted
- The product looks like a generic clone of a competitor

---

### code-reviewer (opus)

**Phase**: VALIDATE (gate reviewer, isolated worktree)

**Responsibilities**:
- 2-stage review: Stage 1 = spec compliance (does it match PRD?), Stage 2 = code quality
- Severity rating: CRITICAL / HIGH / MEDIUM / LOW
- Only CRITICAL and HIGH block the gate
- Definition vendored at `.claude/agents/code-reviewer.md` in the downstream project
- Enforces: "never approve your own authoring output"

**Must speak up when**:
- CRITICAL or HIGH severity issues found
- PRD features are missing from implementation
- Security vulnerabilities detected (injection, unvalidated input, exposed secrets)

---

### developer (sonnet)

**Phase**: BUILD MVP (STEP 4), HARDEN (STEP 6)

**Responsibilities**:
- Implement stories from `.omc/prd.json`
- Mock data first during MVP phase; real APIs only during Harden
- Heavy work (tests, file search, large code gen) → delegate to subagent to protect main context
- Report summary back to main session, not raw output

**Must speak up when**:
- Same error occurs 3 times (fix-loop circuit breaker — escalate immediately)
- Implementation requires a paid API key not yet provided
- Scope of a story is ambiguous enough to risk building the wrong thing

---

### designer (sonnet)

**Phase**: BUILD MVP (STEP 4)

**Responsibilities**:
- UI/UX design decisions based on CEO's design feel answer from KICKOFF
- Component and layout choices
- Ensures the "wow factor" from essence.md is visually represented
- Does NOT ask CEO about tech choices (CSS framework, component library, etc.)

**Must speak up when**:
- Design drift detected — UI no longer reflects essence.md wow factor
- Accessibility issues that would block mainstream users

---

### pm (sonnet)

**Phase**: BUILD MVP (STEP 4), HARDEN (STEP 6), SHIP (STEP 7)

**Responsibilities**:
- Manage the story backlog in `.project/backlog.md`
- Translate CEO answers from KICKOFF into `.project/PRD.md` features
- Write `.project/essence.md` based on CEO intent
- Flag essence drift discovered during story completion (adversarial questions)
- Prepare handoff documents between phases
- Interface with CEO: plain language only, A/B/C choices, no jargon
- Log all decisions to `.project/decisions.md`

**Must speak up when**:
- A story is added that does not serve the core "Why" in essence.md
- CEO needs to be escalated to (API keys, pivot, legal, branding decisions)
- Context reaches 60% (trigger `/compact`)

---

### qa-tester (sonnet + Playwright MCP)

**Phase**: VALIDATE (gate reviewer, isolated worktree)

**Responsibilities**:
- Functional review via actual browser interaction — NOT code review
- Opens the running app in Playwright, clicks every button, fills every form
- Framing: "You are a frustrated beta tester who wants to break this app. For each broken
  or confusing interaction, write: what you did, what you expected, what actually happened.
  Screenshots are evidence."
- After completing, output is validated by `scripts/validate-qa-evidence.sh`
- If zero Playwright evidence found → must re-run with actual browser interaction

**Playwright MCP required**: qa-tester MUST open the actual running app in a browser.
Code-only review is NOT sufficient. If the app isn't running, start it first.

**Must speak up when**:
- App cannot be started (blocks the entire gate)
- A core user flow produces an error or unexpected result
- UI is confusing enough that a real user would abandon within 30 seconds

---

## Agent Assignment Quick Reference

| Task | Agent | Model |
|------|-------|-------|
| Market analysis | analyst | opus |
| Tech stack recommendation | architect | opus |
| Project scaffold | (executor — no named agent) | — |
| CEO questions / kickoff | pm | sonnet |
| PRD + essence.md authoring | pm | sonnet |
| Feature implementation | developer | sonnet |
| UI/component decisions | designer | sonnet |
| Gate: structural review | architect | opus |
| Gate: essence review | critic | opus |
| Gate: code quality | code-reviewer | opus |
| Gate: functional/browser | qa-tester | sonnet |
| Protected file review | architect | opus |
| Backlog management | pm | sonnet |
| CEO escalation interface | pm | sonnet |

---

## Inter-Agent Collaboration Rules

1. Agents run in **isolated worktrees** during gate reviews — no shared context with the authoring agent.
2. Gate reviewers output **defect lists first** (Pass 1). Scores are optional and only in a separate fresh context (Pass 2).
3. The `developer` and `designer` agents delegate heavy work to subagents; the main session receives summaries only.
4. The `pm` is the sole interface to CEO — no other agent asks the CEO questions directly.
5. The `architect` must be invoked any time a file listed in `.protected-files` is modified.
6. All agents must respect the fix-loop circuit breaker: if the same error occurs 3 times, escalate to CEO via `pm` — do not retry a fourth time.
