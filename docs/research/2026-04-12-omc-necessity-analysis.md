# Research Report: OMC 필요성 전략 분석

**Date**: 2026-04-12
**Agent**: `oh-my-claudecode:architect`
**Question**: 사용자의 요청 — "근본적으로 omc 를 안 써도 되나 검토도 좀 해줘. 내가 omc 쓰고는 있지만 필요한가? 에 대해서 의문이라"
**Output**: verbatim agent report

---

## 1. TL;DR

- **idea-factory 는 OMC 에 정확히 하나의 hard dependency 가 있음**: `start-company` STEP 4 가 `/oh-my-claudecode:ralph` 를 autonomous build loop 로 launch. 나머지 OMC 가 제공하는 것은 미사용, 중복, 또는 대체 가능.
- **사용자의 전역 `CLAUDE.md` 는 80% 사용자 본인의 한국어 개발 룰 + 20% OMC boilerplate**. OMC 블록은 thin meta-instructions, active machinery 아님. OMC 블록 제거해도 인지 비용 거의 없음.
- **권장: Option C (선택적 유지) — `ralph` + 글로벌 `architect`/`critic`/`code-reviewer`/`qa-tester` agent markdown 파일 유지**, 다른 OMC skill/hook 은 mental model 에서 제거, v8 에서 (a) ralph-equivalent loop 를 idea-factory 에 inline 또는 (b) 특정 agent .md 파일을 `templates/agents/` 에 vendor. 완전 strip 은 viable 하지만 현재는 premature.

## 2. What OMC actually provides (concrete, from `~/.claude/plugins/cache/omc/oh-my-claudecode/4.11.4/`)

검증된 내용:

- **19 agent markdown files** at `agents/`: `analyst.md`, `architect.md`, `critic.md`, `code-reviewer.md`, `code-simplifier.md`, `debugger.md`, `designer.md`, `document-specialist.md`, `executor.md`, `explore.md`, `git-master.md`, `planner.md`, `qa-tester.md`, `scientist.md`, `security-reviewer.md`, `test-engineer.md`, `tracer.md`, `verifier.md`, `writer.md`.
- **38 skills** at `skills/`: `autopilot`, `ralph`, `ralplan`, `team`, `ultrawork`, `ccg`, `trace`, `verify`, `debug`, `plan`, `deep-interview`, `deep-dive`, `external-context`, `ai-slop-cleaner`, `skillify`, `learner`, `wiki`, `omc-reference`, `omc-setup`, `omc-doctor`, + setup/release/mcp/notification/hud/visual-verdict/self-improve/sciomc/ultraqa/remember/cancel/ask/deepinit/project-session-manager/writer-memory.
- **Bridge / dist / hooks / scripts / templates** — MCP tool surface (`mcp__plugin_oh-my-claudecode_t__*`): notepad, project-memory, state, session-search, ast_grep, lsp_*, python_repl, trace 등.
- 64-line OMC 블록이 `~/.claude/CLAUDE.md` 상단 (lines 1–64, `<!-- OMC:START -->` / `<!-- OMC:END -->` 로 wrap) 에 주입됨.

Concretely OMC 가 vanilla Claude Code 에 추가하는 것:
1. Named agent taxonomy with prompt files.
2. Skill registry with keyword triggers (`"ralph"`, `"autopilot"`, `"ulw"` 등).
3. MCP tool set (LSP, ast-grep, notepad, project-memory, state, trace).
4. 글로벌 `CLAUDE.md` preamble 이 delegation/verification 원칙 encode.
5. `<system-reminder>` 태그 주입하는 훅 (파일을 너무 많이 읽었다고 막 scold 한 것, 세션 시작 때의 것).

## 3. Overlap analysis

| Capability | OMC has | idea-factory has | 실제 사용? |
|---|---|---|---|
| Named agents (architect/critic/code-reviewer/qa-tester) | Yes, 19 agents in plugin cache | Only `pm.md`, `designer.md`, `developer.md` templates — 글로벌 agents 를 이름으로 참조 | **Yes, start-company STEP 4 경유** (`~/.claude/agents/code-reviewer.md` 참조) |
| Autonomous build loop | `ralph`, `autopilot`, `ultrawork` | Native loop 없음 — SKILL.md:148 에서 `/oh-my-claudecode:ralph` 에 delegate | **Yes, hard dependency** |
| Project scaffolding | No | `start-company` skill — templates, hooks, scripts, CLAUDE.md.tmpl, CI, vercel.json, coderabbit.yaml | idea-factory only |
| 5-stage PR pipeline | `pr-create.sh` at `~/.claude/scripts/` (generic, ~30 lines of issue-linking) | `templates/scripts/create-pr.sh` (5 stages: build → review artifact → Codex Gate → PR → bot polling) | **idea-factory 버전이 엄격히 우수**; OMC 의 것은 non-idea-factory repos 용 fallback |
| Gate reviewer orchestration | Implicit via team/ralph | SKILL.md:166–213 에 명시적 (worktree 격리의 4 reviewers, two-pass defect-first evaluation) | idea-factory only |
| Context management (compact, checkpoint) | `remember`, `wiki`, notepad tools | 60% rule, checkpoint.md, handoff docs 가 SKILL.md 에 built-in | Overlapping, idea-factory 의 것은 project-bound |
| Notepad / project-memory | MCP tools (`notepad_*`, `project_memory_*`) | `.omc/` 디렉터리가 state 로 사용됨 (하지만 generic path, OMC plugin 아님) | 불명확 — 훅 통해 간접 사용 가능성 |
| LSP / ast-grep tools | MCP tools | None | 때때로 Claude 가 reach for 할 때만 |
| Skill keyword triggers | 30+ keywords | `start-company` 만 | OMC 더 broad |
| Korean dev rules / Git protocol | No | `CLAUDE.md` user section (lines 67–133) | 사용자 본인, OMC 아님 |

## 4. Dependency graph — idea-factory 가 실제로 OMC 를 invoke 하나?

`~/idea-factory` 에서 `oh-my-claudecode|\.omc|OMC` grep 결과 **10 파일**, 이 중 real coupling 은:

- **`skills/start-company/SKILL.md:148`** — `Then start /oh-my-claudecode:ralph`. **유일한 hard runtime dependency.** 전체 Phase 1–3 build loop 가 ralph 가정.
- **`skills/start-company/SKILL.md:180`** — `Use the global ~/.claude/agents/code-reviewer.md agent`. Soft reference: 파일 존재 시 작동 (OMC 가 글로벌로 ship, vendored 복사본도 identically 작동).
- **`skills/start-company/SKILL.md:168, 173, 186`** — `architect`, `critic`, `qa-tester` 를 agent type 로 참조. 어딘가에 definitions 필요; OMC 가 제공.
- **`README.md:198, 277`** — documentation only, OMC 를 optional prerequisite 로 나열.
- **`install.sh:60`** — "(Optional) oh-my-claudecode for ralph autonomous loop" 출력.
- **`docs/plans/v8-backlog.md`** 및 docs/research/*** — `.omc/audit/`, `.omc/experiments/` 를 **directory paths** 로 논의 (OMC plugin 기능 아님). `.omc/` 는 idea-factory 의 generic state folder, OMC-managed dir 아님.
- **`.gitignore`** — `.omc/` ignore (path convention only).

**Coupling 판정**: idea-factory 는 OMC 에 정확히 두 가지 의존:
1. `ralph` skill (autonomous loop runner).
2. OMC 가 글로벌로 ship 하는 네 개 agent definition 파일 (`architect.md`, `critic.md`, `code-reviewer.md`, `qa-tester.md`).

다른 모든 것 (OMC 의 36 개 다른 skills, 15 개 다른 agents, MCP tools, hooks, pr-create.sh fallback) 은 idea-factory core flow 에 **dead weight**.

## 5. Unique-to-each inventory

**OMC 에 unique (strip 시 손실)**:
- `ralph` autonomous loop runner (대체 가능하지만 inline 은 non-trivial).
- `architect`/`critic`/`code-reviewer`/`qa-tester`/`debugger`/`analyst`/etc. 의 agent markdown files.
- MCP tool surface: LSP, ast-grep, notepad, project-memory, state, trace, session-search, python_repl.
- Skill keyword auto-routing ("autopilot" 타이핑하면 OMC launch).
- agents/tools 용 `omc-reference` meta-catalog.
- delegation 과 verification 을 nudge 하는 64-line 글로벌 preamble.

**idea-factory 에 unique**:
- `start-company` skill (repo 의 유일한 real "product").
- Codex Gate + bot polling 이 있는 5-stage PR pipeline `create-pr.sh`.
- 6-gate pre-deploy consensus script.
- Two-pass defect-first evaluation 의 worktree-isolated gate reviewers (SKILL.md:152–213).
- Protected files + architect review enforcement (`run-architect.sh`).
- Quality ratchet baseline (`quality-baseline.md`).
- MVP → Harden → Ship phases 간 handoff templates.
- 한국어 dev rules, AI signature, labeler workflow, coderabbit.yaml templates.
- Fix-loop circuit breaker (3-fail rule) — doctrinal, code 아님.
- HumanLayer 80-line CLAUDE.md discipline — doctrinal.

## 6. Delta if OMC removed today

severity 로 ranking:

| Impact | What breaks |
|---|---|
| **Significant** | `start-company` STEP 4 가 "Then start `/oh-my-claudecode:ralph`" 에서 halt — loop runner 없음. manual story iteration, `/oh-my-claudecode:autopilot`, vendored loop 으로 replace 필요. |
| **Significant** | SKILL.md:166–186 의 `qa-tester`, `architect`, `critic`, `code-reviewer` Task agent invocations 이 글로벌 agent 파일 없으면 실패. (code-reviewer 는 명시적으로 `~/.claude/agents/` 에서 pull, 오늘 비어있음 — 이미 깨져있을 가능성, 사용자는 모를 수 있음.) |
| **Minor** | MCP tools (LSP/ast-grep/notepad/trace) 사라짐. 사용자는 idea-factory flow 에 hardwire 안 했음. |
| **Minor** | Keyword auto-triggers ("autopilot"/"ralph"/"ulw") fire 중지. `start-company` 는 여전히 있음. |
| **Minor** | `~/.claude/scripts/pr-create.sh` fallback 사라짐, 하지만 모든 idea-factory-scaffolded project 에 자체 `scripts/create-pr.sh` 가 supersede 함 (CLAUDE.md line 112 에서 확인). |
| **Trivial** | `CLAUDE.md` 의 64 lines OMC preamble 사라짐. 67-line 한국어 dev 블록은 영향 없음. |
| **Trivial** | `<system-reminder>` hook injections 중지. (routinely override 중.) |

**🚨 Critical finding**: `~/.claude/agents/` 는 **비어있음** (확인됨). SKILL.md:180 의 "Use the global `~/.claude/agents/code-reviewer.md`" 명령은 그 literal path 에 존재하지 않는 파일을 참조 — 플러그인 cache `~/.claude/plugins/cache/omc/oh-my-claudecode/4.11.4/agents/code-reviewer.md` 에만 존재. Claude Code 가 subagent 이름으로 Task-invoke 할 때 플러그인 메커니즘으로 resolve 할 수 있지만, SKILL.md 의 file-path reference 는 stale. 이건 **idea-factory 의 latent bug**, OMC 가 carry 하고 있다는 증거 아님.

## 7. Alternatives comparison

**A. OMC 그대로 유지**
- Pros: migration cost 0; ralph + agents 계속 작동; OMC 가 upstream updates 계속 수신 (4.11.4, 4월 11 업데이트); MCP tools 때때로 유용.
- Cons: 사용 안 하는 64-line 글로벌 preamble; mental model 혼동 ("OMC teams vs idea-factory gate reviewers?"); OMC hooks 가 override 하는 reminders 주입; version drift 리스크 — OMC 업데이트가 start-company 의 ralph invocation 을 조용히 break 할 수 있음.

**B. OMC 완전 strip, vanilla Claude Code + idea-factory 만**
- Pros: 인지 부하 hard drop; single source of truth; hidden machinery 없음; 글로벌 `CLAUDE.md` 가 실제로 작성한 67 lines 로 축소.
- Cons: 먼저 (a) ralph-equivalent loop 를 idea-factory 에 inline 또는 STEP 4 를 manual story iteration 으로 downgrade, (b) `architect.md`/`critic.md`/`code-reviewer.md`/`qa-tester.md` 를 `templates/agents/` 에 vendor, (c) `pr-create.sh` fallback 을 skill 자체에 이동. 추정 1–2 일. 그전까지 strip 은 `start-company` break.

**C. 선택적 adoption (RECOMMENDED)**
- 유지: `ralph` skill, 4 개 agent `.md` 파일, `pr-create.sh` fallback. 그게 다.
- Drop mentally: OMC preamble 블록, autopilot, ultrawork, team, ralplan, ccg, trace, verify, 다른 모든 skills. Uninstall 하지 말고 — 생각만 안 하기.
- Cost: near-zero. Benefit: "OMC 필요한가" 질문 중단.

**D. OMC 포크, 유용 부분 흡수, 나머지 drop**
- Viable 하지만 high-cost. OMC 버그를 고치고 싶거나 v8 이 자체 skill registry 원할 때만 의미.
- Minimal fork 은 ~6 파일: ralph.md, architect.md, critic.md, code-reviewer.md, qa-tester.md, debugger.md. ~500 lines total. half-day 에 `templates/agents/` 와 새 `templates/skills/ralph/` 에 absorb 가능.

## 8. Recommendation

**Option C 지금, v8 에 B 로의 구체적 exit ramp 포함.**

정직한 reasoning:

1. **OMC 는 오늘 사용자에게 carry 하지 않지만 actively harm 도 안 함.** 64-line preamble 은 negligible. ralph skill 은 유일한 genuine value-add, 실제 사용 중. 36 개 다른 skills 는 성공적으로 무시 중인 noise.

2. **Redundancy 는 real 하지만 bounded**: OMC 의 `pr-create.sh` vs idea-factory 의 `create-pr.sh`, OMC 의 team orchestration vs idea-factory 의 gate reviewers, OMC 의 `remember`/`wiki` vs idea-factory 의 handoff docs. 모든 경우에 idea-factory 버전이 더 specific, committed, battle-tested (market-dashboard-v5 의 13 phases). **사용자는 important 영역에서 이미 OMC 를 out-engineer 했음.**

3. **올바른 mental model**: OMC = "any Claude Code project 용 generic harness". idea-factory = "내가 신경쓰는 하나의 workflow (one-line idea → shipped MVP) 를 위한 opinionated harness". Overlap 은 generic plumbing 에; value 는 idea-factory opinions 에. OMC 는 infrastructure 로 유지, idea-factory 는 product 로 유지.

4. **🚨 Latent bug 먼저 수정**: `SKILL.md:180` 이 literal path 에 존재하지 않는 `~/.claude/agents/code-reviewer.md` 참조. 또는 (a) 파일을 `templates/agents/code-reviewer.md` 로 vendor 하고 reference 업데이트, 또는 (b) subagent-name 으로 Task-invoking 이 플러그인으로 여전히 작동하는지 테스트. **OMC 질문보다 이게 더 urgent.**

5. **v8 exit ramp**: v8 이 자체 autonomous loop 추가하면 (`docs/plans/v8-backlog.md` 가 `.omc/experiments/failed.jsonl` 패턴으로 암시), 그 loop 이 `ralph` 를 자연스럽게 replace. 그 시점에 single SKILL.md edit 으로 OMC dependency delete 하고 Option B 로 cleanly 이동. v8 전엔 하지 마 — replace 할 코드를 rewriting.

6. **멈출 것**: OMC preamble 이 행동을 constrain 하는 것처럼 읽지 말 것. 안 함 — Claude 용 nudge, 사용자 용 아님. 실제로 프로젝트를 govern 하는 건 한국어 dev rules (lines 67–133). `CLAUDE.md` lines 1–64 mental delete.

**Concrete next actions** (순서대로):
1. `SKILL.md:180` 수정 — `templates/agents/` 에 `code-reviewer.md` vendor 하거나 테스트 프로젝트에서 subagent-name resolution 작동 verify.
2. `architect.md`, `critic.md`, `qa-tester.md` 를 `templates/agents/` 에 vendor 해서 idea-factory-scaffolded project 가 사용자 머신에 OMC 설치 의존하지 않게. (README 가 이미 "Optional" 이라고 말함.) idea-factory clone 하는 Claude 사용자에 대한 external dependency 제거까지 one `cp` away.
3. v8 planning 에 story 추가: "ralph-equivalent loop 를 inline 또는 `/oh-my-claudecode:ralph` 를 permanent dep 로 commit — 하나 선택." ambiguity 에 그만 살기.
4. OMC 설치된 채로 둬. Strip 하지 마. Uninstall 하지 마. 그냥 걱정 중지.

## References

- `~/.claude/CLAUDE.md:1-64` — OMC preamble block (actively 사용 안 하는 64 lines).
- `~/.claude/CLAUDE.md:67-133` — 한국어 dev rules (실제로 작업을 govern 하는 부분).
- `~/idea-factory/skills/start-company/SKILL.md:148` — OMC 의 sole hard runtime dependency (`Then start /oh-my-claudecode:ralph`).
- `~/idea-factory/skills/start-company/SKILL.md:166-213` — OMC-provided agent definitions 에 의존하는 4 gate reviewers (architect/critic/code-reviewer/qa-tester).
- `~/idea-factory/skills/start-company/SKILL.md:180` — `~/.claude/agents/code-reviewer.md` 의 stale reference (path 존재하지 않음; 실제 파일은 plugin cache 에). **Latent bug.**
- `~/idea-factory/templates/agents/` — `pm.md`, `designer.md`, `developer.md` 만 포함. 4 개 reviewer agents 누락.
- `~/idea-factory/templates/scripts/create-pr.sh` — idea-factory 의 자체 5-stage PR pipeline, scaffolded projects 에서 OMC 의 `pr-create.sh` supersede.
- `~/.claude/scripts/pr-create.sh` — 글로벌 OMC-style fallback PR script, ~30 line stub.
- `~/.claude/plugins/cache/omc/oh-my-claudecode/4.11.4/agents/` — OMC 의 19 agent 파일 실제 위치.
- `~/.claude/plugins/cache/omc/oh-my-claudecode/4.11.4/skills/` — OMC 의 38 skills 실제 위치.
- `~/.claude/agents/` — 비어있음 확인; 이 literal path 로의 SKILL.md reference 는 broken.
- `~/idea-factory/README.md:198, 277` — OMC 를 optional dependency 로 나열, recommendation 과 consistent.
- `~/idea-factory/install.sh:60` — 스크립트가 이미 OMC 를 optional 로 취급, user-facing positioning 이미 정확.
