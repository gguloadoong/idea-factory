# AGENTS.md — idea-factory

**idea-factory** turns a one-line business idea into a working MVP via a team of AI agents
running on Claude Code + oh-my-claudecode (OMC).

---

## Entry Points

| File | Purpose |
|---|---|
| [CLAUDE.md](./CLAUDE.md) | Governance for contributors working inside this meta-repo |
| [skills/start-company/SKILL.md](./skills/start-company/SKILL.md) | Execution flow — the `/start-company` trigger logic |
| [skills/start-company/HARNESS-GUIDE.md](./skills/start-company/HARNESS-GUIDE.md) | Design rationale — why every architectural decision was made |

**Read CLAUDE.md first** before making any changes to this repo.

---

## When Working in This Repo

1. Check `sync-manifest.json` — changes to `managed` files propagate to 10 downstream repos
2. Check `downstream-registry.json` — the full list of tracked repos
3. Protected files require PR: `sync-manifest.json`, `downstream-registry.json`, `templates/CLAUDE.md.tmpl`
4. Model routing: Sonnet 4.6 default, Opus 4.7 for architecture/security reviews only

---

## External Docs

- [README.md](./README.md) — Project overview, install, usage, design decisions
- [ARCHITECTURE.md](./ARCHITECTURE.md) — System layers, agent roles, data flow, quality gates
- [CHANGELOG.md](./CHANGELOG.md) — Version history

---

## Language

- Human-facing content: **Korean** (primary audience is a non-technical Korean-speaking CEO)
- Code, configs, templates: **English**
- Commit messages: **Korean** (한국어 원자적 커밋)
