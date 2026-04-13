---
name: start-company
description: "Give a one-line idea, get a virtual startup that builds your MVP autonomously. Use when you want to create a new product from scratch."
argument-hint: "[your idea in one line] — passed as $ARGUMENTS"
user_invocable: true
---

# idea-factory

You received a business idea: **$ARGUMENTS**

Build a virtual startup and deliver a working MVP.

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
- Service name, folder name, service type (SaaS/O2O/commerce/content/data/internal-tool), project type (web-app/cron-bot/trading/payment)
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

1. `CLAUDE.md` — choose template based on project type:
   - **cron-bot/trading**: from `templates/cron-bot/CLAUDE.md.tmpl` (no UI/Playwright, yes reliability/monitoring rules)
   - **web-app/payment**: from `templates/CLAUDE.md.tmpl`
   Replace `{{variables}}`.
   **CRITICAL**: CLAUDE.md MUST be a full file (30-80 lines) with project rules, quality gates,
   and AI regression prevention. NEVER replace it with a single `@AGENTS.md` pointer.
   If variable substitution fails, copy the template as-is and fill manually in STEP 3.
   Verify after creation: `wc -l CLAUDE.md` must be >= 30 lines.
2. `.claude/agents/` — from `templates/agents/`, minimum team only
   Agent templates should include: role definition, key responsibilities,
   "situations where this agent MUST speak up" (e.g., architect must flag
   when protected files are changed), and inter-agent collaboration rules.
   Reference: market-dashboard-v5 agents are 90+ lines each with career anchors
   and project-specific context. Aim for at least 50 lines per agent.
3. `.claude/hooks/` — copy from `templates/hooks/`
4. `.claude/settings.json` — merge base `templates/settings.json` with type-specific deny-list:
   `bash scripts/merge-settings.sh <project-type>` where project-type maps from service type:
   - SaaS/content/internal-tool → `web-app`
   - O2O/commerce → `payment`
   - data → `cron-bot`
   - trading (if detected in idea keywords) → `trading`
   Write the merged output to `.claude/settings.json`.
5. `.project/essence.md` — empty, filled in STEP 3
6. `.project/PRD.md` — empty, filled in STEP 3
7. `.project/decisions.md` — initialized with creation ADR
8. `.project/backlog.md` — empty
9. `.github/workflows/ci.yml` — from `templates/.github/workflows/ci.yml`
10. `.github/workflows/label-pr.yml` — from `templates/.github/workflows/label-pr.yml`
11. `.github/labeler.yml` — from `templates/.github/labeler.yml`
12. `vercel.json` — from `templates/vercel.json` (preview 배포 비활성화, production만).
    **Vercel 연결 후 필수 설정**: Dashboard > Settings > Git > "Production Branch" = `main`, Preview Deployments = OFF
13. `.coderabbit.yaml` — from `templates/.coderabbit.yaml`
14. `src/CONTRACT.md` — from `templates/documents/CONTRACT.md.tmpl`, replace `{{FEATURE_NAME}}` with service name
15. `.project/handoff/` — empty directory for phase transition documents (template: `templates/documents/handoff.md.tmpl`)
16. `scripts/create-pr.sh` — from `templates/scripts/create-pr.sh` (5-stage PR pipeline)
17. `scripts/pre-deploy-consensus.sh` — from `templates/scripts/pre-deploy-consensus.sh` (6-gate deploy consensus)
18. `scripts/review-summary.sh` — from `templates/scripts/review-summary.sh` (review summary auto-post)
19. `scripts/run-architect.sh` — from `templates/scripts/run-architect.sh` (protected file review)
20. `scripts/update-project-docs.sh` — from `templates/scripts/update-project-docs.sh` (auto doc update on PR)
21. `.protected-files` — empty, filled after Phase 1 (files requiring architect review)
22. `.githooks/pre-push` — from `templates/.githooks/pre-push` (stale review warning)
23. `.github/workflows/token-health.yml` — from `templates/.github/workflows/token-health.yml` (weekly token check)
24. `.project/quality-baseline.md` — empty, generated after Phase 2 (from `templates/documents/quality-baseline.md.tmpl`)
25. **cron-bot/trading only** — additional files from `templates/cron-bot/scripts/`:
    - `scripts/backtest.sh` — backtest runner (date range + config)
    - `scripts/rollback.sh` — version rollback with audit logging
    - `scripts/health-check.sh` — JSON health status reporter
    - `templates/workflows/tuning-session.md` → `.project/tuning-protocol.md` (parameter tuning protocol)
    - `.omc/experiments/` directory with README from `templates/experiments/README.md`
26. `git init` + `git config core.hooksPath .githooks` + initial commit

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

  HANDOFF-MVP: Write MVP→Harden handoff document (see template)

Phase 2 — Harden (real APIs, tests, security)
  HARDEN-001: Replace mock with real data
  HARDEN-002: Error handling + loading states
  HARDEN-003: Tests
  HARDEN-004: Security audit
  HARDEN-005: Generate .protected-files list + run-architect.sh integration
  HARDEN-006: Generate quality-baseline.md (ratchet rules — quality never goes down)
  VALIDATE-002: Production Gate (gate: true)

  HANDOFF-HARDEN: Write Harden→Ship handoff document (see template)

Phase 3 — Ship
  SHIP-001: gh repo create → bash scripts/setup-github.sh (branch protection + labels)
  SHIP-002: Full 5-stage PR pipeline — build → code-reviewer artifact check →
            Codex Gate → create-pr.sh (issue linking + bot polling) → review-summary.sh
  SHIP-003: Deploy with pre-deploy-consensus.sh (6 gates must pass) + smoke test + retro
  SHIP-004: Set up .githooks/pre-push + `git config core.hooksPath .githooks`
  SHIP-005: Run update-project-docs.sh for final doc sync
```

Then start `/oh-my-claudecode:ralph`.

**Gate stories** trigger parallel independent reviews.

> **CRITICAL: Fresh Context Isolation**
> Every gate reviewer MUST run with `isolation: "worktree"` (a separate copy of the project).
> Reason: Anthropic's research proves that an agent evaluating its own work in the same
> context always inflates quality ("Evaluator Leniency"). Fresh context = honest evaluation.
> Reference: https://www.anthropic.com/engineering/harness-design-long-running-apps

> **CRITICAL: Defect-Detection FIRST, Scoring SECOND (if at all)**
> Step 1: Always start with adversarial defect-detection framing ("find every flaw").
> Step 2: Only AFTER defects are listed, optionally score on 4 axes in a FRESH context.
> WHY: Scoring without prior defect detection triggers "Rubric Gaming" — the AI optimizes
> for high scores instead of finding problems. But scoring CAN work when the evaluator
> has already committed to a defect list (Anthropic used scoring with tuned criteria
> and a separated evaluator). The key: defects first, scores second, never same context.

Four reviewers run in parallel, each in isolated worktree:

- `architect` (opus, isolation: worktree): Structure adversarial review.
  Prompt framing: "You are a hostile tech lead reviewing a junior's PR. Find every
  structural problem that will block Phase 2. List every shortcut, every missing
  abstraction, every coupling that will cause pain later. Be brutal."

- `critic` (opus, isolation: worktree): Essence adversarial review.
  Prompt framing: "You are a competitor analyzing this product. List every reason
  a user would abandon this within 30 seconds. Find every place where the product
  drifts from its core 'Why' in essence.md. What would you mock if you saw this
  at a demo day?"

- `code-reviewer` (opus, isolation: worktree): Code quality review.
  Task-invoke the `code-reviewer` subagent. Its definition is vendored at
  `.claude/agents/code-reviewer.md` (scaffolded from idea-factory's
  `templates/agents/code-reviewer.md` at project creation). It runs a 2-stage
  review: Stage 1 = spec compliance (does it match PRD?), Stage 2 = code quality
  (security, SOLID, logic, performance). Issues are severity-rated (CRITICAL/HIGH/
  MEDIUM/LOW). Only CRITICAL and HIGH block the gate.
  This agent already enforces "never approve your own authoring output."

- `qa-tester` (sonnet, isolation: worktree, tools: Playwright MCP): Functional review.
  Prompt framing: "You are a frustrated beta tester who wants to break this app.
  Open the running app in Playwright. Click every button, fill every form, try every
  edge case. For each broken or confusing interaction, write: what you did, what you
  expected, what actually happened. Screenshots are evidence."
  **Playwright MCP required**: qa-tester MUST open the actual running app in a browser
  and interact with it. Code-only review is NOT sufficient. If the app isn't running,
  start it first. Test real clicks, real navigation, real data display.

Cross-model review (mandatory when Codex CLI available):
- If Codex CLI is installed, MUST run Codex Gate on the diff.
  This is NOT optional — Gate 1 proved ROI (caught 2 bugs Claude missed).
- If Codex CLI is not installed, log a warning in gate-results and skip.
- Track results in `.project/codex-gate-log.md` for ROI evaluation.

Gate evaluation (two-pass):
- **Pass 1 — Defect Hunt** (mandatory): Each reviewer outputs a **defect list** first.
  No scores allowed in this pass. Pure adversarial problem-finding.
- **Pass 2 — Structured Score** (optional, fresh context): After defect lists are committed,
  a separate agent MAY score on 4 axes: Functionality / Essence Alignment / Code Quality / UX.
  Hard threshold: if any axis < 6/10, auto-fail. This pass is useful for tracking progress
  across iterations but is NOT required for gate passage.
- **Gate result logging** (mandatory): Save ALL reviewer outputs (defect lists + optional scores)
  to `.project/gate-results/VALIDATE-{NNN}.md`. This enables post-mortem analysis and QA tuning.
- Gate passes when: total critical defects = 0 across all four Pass 1 reviewers
- If any critical defect found → add fix stories before the gate and retry
- If all pass → ask CEO "Is this the right direction?" then proceed
- After qa-tester completes, run `scripts/validate-qa-evidence.sh` on the output.
  If zero Playwright evidence → qa-tester must re-run with actual browser interaction.

Why two-pass works (for people reading this on GitHub):
- Pass 1 alone: "Find every flaw as a hostile reviewer" → AI finds 5-15 real issues
- Scoring alone: "Rate this 1-10" → AI gives 9/10 and moves on (Evaluator Leniency)
- Two-pass: defects are already committed before scoring begins, so the scorer can't ignore them
- Anthropic used scoring successfully — but with separated evaluators and tuned criteria
- The failure mode is scoring WITHOUT prior defect detection in the SAME context

### Essence Verification (every story completion)

After each story, ask these adversarial questions (NOT scores):
1. "If a user described this app in one sentence, would it match essence.md? If not, what's the gap?"
2. "Would a competitor look at this feature and say 'that's clever'? Or 'that's generic'?"
3. "If we removed this feature entirely, would the core value proposition survive?"

If any answer reveals drift → flag in backlog with specific description of the drift.
If drift is severe (feature contradicts the "Why") → escalate to CEO with pivot options.

> Why no scores: Numeric drift scores (e.g., "drift = 5/10") trigger the same Evaluator Leniency
> as scoring code quality. The AI will always report low drift to keep moving. Adversarial questions
> force concrete, specific answers that reveal real problems.

### CEO Escalation (only these)
- Paid API keys, billing, account connections
- Major pivot needed
- Physical/legal/administrative help needed
- Branding/policy decisions requiring CEO intent

### Context Health Management (auto-compact + subagent isolation)
- **60% Rule**: After every story, check context usage.
  60% → `/compact Keep: essence, Phase, decisions, current story, bugs`
  80% → checkpoint.md + warn CEO. 95% → STOP + new session.
  NEVER let context reach 95% without compacting — degraded memory = garbage summary.
- **Subagent Isolation**: Heavy work (tests, file search, code gen) → subagent.
  Main session stays lightweight: direction, decisions, story management only.
  Subagent returns summary, not raw output. This prevents context bloat.
- **Checkpoint**: Every 10 stories or ~2 hours → `.project/checkpoint.md`
- **Session Start**: CLAUDE.md includes 7-file read checklist for new sessions.
- Reference: Anthropic "Context Reset with structured handoff" + /compact 60% rule
  (https://www.mindstudio.ai/blog/claude-code-compact-command-context-management)

### CLAUDE.md Size Rule (from HumanLayer research)
- AI can follow ~150-200 instructions before compliance drops
- Claude Code system prompt already uses ~50 of those
- Generated CLAUDE.md MUST stay under 80 lines (leaves room for growth)
- Use progressive disclosure: put details in separate files, pointers in CLAUDE.md
- Reference: https://www.humanlayer.dev/blog/writing-a-good-claude-md

### Fix-Loop Circuit Breaker (from Reddit/Stormy AI community)
- If any story fails the same way 3 times → STOP and escalate
- Do NOT let the agent enter an infinite fix-loop (burns tokens, produces garbage)
- After 3 failures: write a diagnosis to `.project/decisions.md` and flag to CEO
- This overrides "Heal, Don't Repeat" — healing has a budget

### Ghost Bug Awareness
- "Ghost Bugs" = code that looks perfect but fails in edge cases
- Playwright testing (qa-tester) is the primary defense
- After Phase 2 (Harden), add edge case scenarios to Playwright tests:
  empty inputs, special characters, network timeouts, rapid double-clicks

### Quality Ratchet (from market-dashboard-v5, proven across 13 phases)
- After Phase 2 (Harden), generate `.project/quality-baseline.md`
- Rule: quality metrics can only go UP, never DOWN
- Covers: build status, test count, data accuracy, UI states, API fallback, deploy checklist
- Every PR must not regress any baseline metric
- If regression detected → block PR until fixed or CEO approves exception

### Protected Files (architect review enforcement)
- After Phase 1, identify core algorithm/business logic files → write to `.protected-files`
- Any change to listed files triggers mandatory architect (opus) review
- `run-architect.sh` generates review artifact; `create-pr.sh` verifies artifact exists and is fresh
- Stale artifact (wrong commit hash) → PR blocked

### Never
- Never ask CEO technical implementation questions
- Never skip MVP phase and go straight to real APIs
- Never deploy before VALIDATE gate passes
- Never repeat the same failed approach twice
- Never start coding without essence.md
- Never let CLAUDE.md exceed 80 lines (use progressive disclosure instead)
- Never let a fix-loop run more than 3 attempts on the same error
