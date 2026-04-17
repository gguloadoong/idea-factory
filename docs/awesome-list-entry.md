# Awesome-List 등재 제출 초안

idea-factory를 Claude Code 커뮤니티 큐레이션 리스트에 등재하기 위한 제출 초안 모음.
실제 포크·PR 제출은 각 레포의 기여 규약을 확인하고 대표 승인 후 진행.

---

## 1. hesreallyhim/awesome-claude-code

**타겟**: https://github.com/hesreallyhim/awesome-claude-code
**섹션 후보**: Templates / Workflows
**제출 방식**: README.md에 PR

### 제안 엔트리 (영문)

```markdown
- [idea-factory](https://github.com/gguloadoong/idea-factory) — Turns a one-line business idea into a working MVP. Ships a full virtual startup team (PM / Developer / Designer / Architect / Critic / Code-Reviewer / QA) with a 4-reviewer isolated-worktree gate, Quality Ratchet, and MVP-First phase pipeline. Template-install via `claude plugin install` or `bash install.sh`. Korean + English docs.
```

### PR 본문 템플릿

```markdown
## Add idea-factory to the list

**Category**: Templates / Workflows

**What it is**: Template-install AI company factory for Claude Code. `/start-company "a portfolio tracker for busy investors"` scaffolds a new repo with 7 agents, 18+ hooks, and quality gates, then runs an autonomous ralph loop to build an MVP.

**Why it's awesome**:
- 4-reviewer parallel gate in isolated worktrees (architect + critic + code-reviewer + qa-tester) eliminates evaluator leniency
- 80-line CLAUDE.md discipline (informed by HumanLayer compliance research)
- Korean + English documentation for non-English-native founders
- OAuth 2.1 MCP bundle (Supabase + Vercel), Routines cloud automation, Agent Teams presets
- Plugin Marketplace ready (v8.x)

**Repo**: https://github.com/gguloadoong/idea-factory
**License**: MIT
```

---

## 2. rohitg00/awesome-claude-code-toolkit

**타겟**: https://github.com/rohitg00/awesome-claude-code-toolkit
**섹션 후보**: Agents / Plugins / Templates
**특징**: 135 agents · 176+ plugins 큐레이션

### 제안 엔트리

```markdown
- **idea-factory** — One-line idea → working MVP. 7-agent startup team (pm / developer / designer / architect / critic / code-reviewer / qa-tester), 4-reviewer worktree gate, MVP-First pipeline. [Repo](https://github.com/gguloadoong/idea-factory)
```

---

## 3. VoltAgent/awesome-claude-code-subagents

**타겟**: https://github.com/VoltAgent/awesome-claude-code-subagents
**섹션 후보**: Workflows / Orchestration
**특징**: subagent 패턴 중심

### 제안 엔트리

```markdown
- [idea-factory](https://github.com/gguloadoong/idea-factory) — Full virtual startup team via Claude Code subagents. Each gate reviewer (architect / critic / code-reviewer / qa-tester) runs in an isolated worktree with fresh context — anti-leniency pattern proven across 13 market-dashboard-v5 phases.
```

---

## 4. ComposioHQ/awesome-claude-plugins

**타겟**: https://github.com/ComposioHQ/awesome-claude-plugins
**섹션 후보**: Plugin catalog
**특징**: 176+ plugins 큐레이션

### 제안 엔트리

```markdown
- **idea-factory** · [Plugin](https://github.com/gguloadoong/idea-factory) · MVP Generator · KR/EN
  - One-line business idea → autonomous MVP build via 7-agent startup team
  - MCP bundle (Supabase + Vercel, OAuth 2.1 default) + Routines cloud automation + Agent Teams
```

---

## 5. anthropics/claude-plugins-official (공식 마켓플레이스)

**타겟**: https://github.com/anthropics/claude-plugins-official
**특징**: Anthropic 공식. 101개 플러그인 (Anthropic 33 + 파트너 68) 중 하나가 되는 제출.
**절차**: [docs/plugin-submission-checklist.md](./plugin-submission-checklist.md) 참조.

공식 심사 필요 — 품질·보안·호환성 검토 후 등재 여부 결정.

---

## 제출 전 공통 체크리스트

각 awesome-list에 PR 제출 전 확인:

- [ ] 타겟 레포의 기존 엔트리 형식 재확인 (알파벳 정렬? 섹션 구분? 이모지 사용?)
- [ ] 섹션 정확히 선정 (Templates vs Workflows vs Agents vs Plugins)
- [ ] 한 줄 설명에 핵심 차별점 포함 (4-reviewer gate / Korean docs / MVP-First)
- [ ] 타겟 레포의 CONTRIBUTING.md / CoC 숙지
- [ ] PR 본문에 what / why / link / license 포함
- [ ] repo description · topics · is_template 최신 상태 확인 (이미 설정 완료)

## 이미 완료된 저장소 상태

| 항목 | 상태 |
|---|---|
| `license` | MIT |
| `is_template` | true (Use this template 버튼 활성화) |
| `topics` | ai-agents · autonomous-builder · claude-code · korean · llm-orchestration · mvp-generator · startup-factory · template-repository |
| `description` | "One idea in. Working MVP out. Turn Claude Code into a virtual startup team." |
| `homepage` | https://github.com/gguloadoong/idea-factory#install |
| `.claude-plugin/plugin.json` | v8.0.0 (공식 plugins-reference 스키마 준수) |
| `.claude-plugin/marketplace-readme.md` | 영문 pitch (73줄) |

## 참고 문서

- [docs/plugin-submission-checklist.md](./plugin-submission-checklist.md) — 공식 + 커뮤니티 마켓플레이스 제출 절차
- [.claude-plugin/marketplace-readme.md](../.claude-plugin/marketplace-readme.md) — 마켓 리스팅용 영문 README
- [ARCHITECTURE.md](../ARCHITECTURE.md#claude-code-2026-q1-integrations) — Claude Code Q1 통합 섹션
