---
name: start-company
description: "Give a one-line idea, get a virtual startup that builds your MVP autonomously. Use when you want to create a new product from scratch."
argument-hint: "[your idea in one line] — passed as $ARGUMENTS"
user_invocable: true
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Task
disable-model-invocation: false
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

## Execution Flow Overview

Seven phases run in sequence. Full per-phase detail is in `phases.md`.

1. **ANALYZE** — Two parallel agents (analyst + architect, both opus) dissect the idea
2. **SCAFFOLD** — Create project from `~/.claude/templates/company/` (26 items)
3. **KICKOFF** — Ask CEO 3–5 plain-language questions; fill CLAUDE.md + PRD + essence.md
4. **BUILD MVP** — Generate `.omc/prd.json` stories; start `/oh-my-claudecode:ralph`
5. **VALIDATE** — 4 isolated reviewers (architect / critic / code-reviewer / qa-tester) per gate
6. **HARDEN** — Real APIs, tests, security audit, protected-files, quality-baseline
7. **SHIP** — GitHub + 5-stage PR pipeline + 6-gate deploy consensus + retro

For per-phase step-by-step instructions, see `phases.md`.
For agent role definitions and assignment rules, see `agents.md`.

## Critical Invariants (apply across all phases)

### CLAUDE.md Size Rule
- Generated CLAUDE.md MUST stay under 80 lines (leaves room for growth)
- NEVER replace CLAUDE.md with a single `@AGENTS.md` pointer
- Use progressive disclosure: details in separate files, pointers in CLAUDE.md
- Reference: https://www.humanlayer.dev/blog/writing-a-good-claude-md

### Fix-Loop Circuit Breaker
- If any story fails the same way 3 times → STOP and escalate to CEO
- After 3 failures: write diagnosis to `.project/decisions.md` and flag to CEO
- This overrides "Heal, Don't Repeat" — healing has a budget

### Fresh Context Isolation (gates)
- Every gate reviewer MUST run with `isolation: "worktree"`
- Reason: same-context evaluation always inflates quality ("Evaluator Leniency")

### CEO Escalation (only these triggers)
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
- Never let CLAUDE.md exceed 80 lines
- Never let a fix-loop run more than 3 attempts on the same error
