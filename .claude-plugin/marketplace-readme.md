# idea-factory

> One idea in. Working MVP out.

**idea-factory** turns Claude Code into a virtual startup team. Describe what you want to build in a single line — a team of AI agents handles analysis, scaffolding, building, reviewing, and shipping autonomously. You stay in the CEO seat: no code required.

---

## What Makes This Different

- **Full startup team, not just a coder.** Seven specialized agents (PM, Developer, Designer, Architect, Critic, Code-Reviewer, QA-Tester) collaborate in parallel with defined roles and handoffs — not a single model doing everything.
- **MVP-First philosophy.** Mock data and core flow first. Real APIs and deployment only after the prototype is validated. This prevents the most common AI-assisted failure: connecting payment APIs before anyone wants the product.
- **4-reviewer gate with fresh-context isolation.** Every gate runs Architect + Critic + Code-Reviewer + QA-Tester in isolated worktrees. Same-session self-review is explicitly blocked to eliminate "Evaluator Leniency" bias.
- **Essence verification on every feature.** An `essence.md` captures your service's Why, Wow Factor, and Key Metric. Every story is checked against it — drift triggers a flag and a suggested pivot before it compounds.
- **Fix-loop circuit breaker.** Same failure 3 times in a row stops the loop and escalates to you. No infinite token-burning retries.

---

## Install

Once the plugin is listed in a marketplace, install it with:

```bash
claude plugin install idea-factory@claude-plugins-official
```

Or load it locally for development and testing:

```bash
claude --plugin-dir ./idea-factory
```

---

## Quick Start

```
/idea-factory:start-company a portfolio tracker for busy investors
```

The system will:
1. Analyze your idea (analyst + architect in parallel)
2. Scaffold the project from battle-tested templates
3. Ask you 3–5 plain-language questions (design feel, scope, revenue model)
4. Build the MVP autonomously using a ralph state-machine loop
5. Validate with 4 independent reviewers in isolated worktrees
6. Prompt you before advancing to Harden or Ship phases

---

## Prerequisites

| Required | Optional |
|----------|----------|
| Claude Code CLI (latest) | oh-my-claudecode (for `ralph` autonomous loop) |
| Node.js 18+ | Gemini CLI (external cross-model perspective) |
| Git | |

---

## Safety and Security Declarations

- **No hardcoded tokens or secrets.** All MCP server configurations use environment variable references (`${SUPABASE_ACCESS_TOKEN}`, `${VERCEL_API_TOKEN}`). No static credentials are bundled.
- **OAuth 2.1 MCP defaults.** Bundled MCP presets (Supabase, Vercel) reference the OAuth 2.1 browser-authorization flow — users authorize via browser, no long-lived tokens stored in config files.
- **Deny-list safety floor.** `settings.json` ships with a `permissions.deny` list that blocks destructive operations (`rm -rf /`, `sudo *`) and sensitive reads (`.env*`, credentials, secrets) by default. This floor is enforced on all generated downstream projects.
- **No blocking PreToolUse hooks.** All PreToolUse hooks are exit-0 audit-log only. Autonomous workflows stay zero-friction while the deny-list provides the safety boundary.
- **CLAUDE.md 80-line limit.** Generated project CLAUDE.md files are kept under 80 lines. Compliance with AI agent instructions degrades beyond ~150 instructions (HumanLayer research, March 2026).

---

## License

MIT — [github.com/gguloadoong/idea-factory](https://github.com/gguloadoong/idea-factory)
