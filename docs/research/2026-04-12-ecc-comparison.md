# Research Report: everything-claude-code vs idea-factory 비교 분석

**Date**: 2026-04-12
**Agent**: `oh-my-claudecode:document-specialist`
**Question**: 사용자의 요청 — "idea-factory 가 이런 하네스를 뛰어넘는 게 되고 싶어. 여기서 배울 것 있으면 배우자."
**Target repo**: https://github.com/affaan-m/everything-claude-code
**Output**: verbatim agent report

---

## 1. Project Snapshot

**everything-claude-code** (ECC) 는 production-grade Claude Code 플러그인 프레임워크 — "주방 싱크" 파워유저 툴킷. 자율 제품 빌딩 워크플로우가 아니라 **개발자 생산성 증폭기**. 자체 표현: "a complete system: skills, instincts, memory optimization, continuous learning, security scanning, and research-first development."

**크기 메트릭**: 1,947 파일, v1.10.0, 181 skills, 47 agents, 12+ 언어 에코시스템, ~70 hook 스크립트, 60+ slash commands, 전체 테스트 스위트 (90+ 테스트 파일), npm 패키지 (`ecc-universal`, `ecc-agentshield`), GitHub App (~150 installs), 주장 140K stars/21K forks (의심스러움 — 인플레이션 가능성). Anthropic Hackathon Winner. Claude Code, Codex, Cursor, OpenCode, Gemini 간 지원. 언어: TypeScript, Python, Go, Java, Kotlin, Rust, Dart, C++, C#, Flutter, Perl.

**idea-factory** 는 약 30 파일, single-workflow, CEO 친화, product-focused. ECC 는 파일 수로 약 65배 큼.

---

## 2. Structure Overview

```
everything-claude-code/
├── agents/           # 47 specialized subagents (planner, reviewers, build resolvers per language, GAN agents)
├── skills/           # 181 skills (domain knowledge, workflows, patterns)
├── commands/         # 60+ slash commands (/tdd, /plan, /e2e, /learn, /skill-create, /code-review, etc.)
├── hooks/            # hooks.json + ~20 hook scripts (pre/post-tool, session, stop, compact)
├── rules/            # Always-on guidelines (security, node, etc.)
├── mcp-configs/      # MCP server configurations
├── scripts/          # Cross-platform Node.js hook runners, install pipeline, state store
├── tests/            # 90+ test files for hooks, scripts, lib
├── ecc2/             # Rust control-plane alpha (dashboard, sessions, daemon commands)
├── .claude/          # commands/, rules/, team config, research playbook
├── .codex/           # Codex agent configs (.toml)
├── .cursor/          # Cursor hook adapters
├── .codebuddy/       # CodeBuddy install/uninstall scripts
├── SOUL.md           # Identity manifesto
├── the-longform-guide.md, the-shortform-guide.md, the-security-guide.md
└── EVALUATION.md, REPO-ASSESSMENT.md, WORKING-CONTEXT.md
```

---

## 3. Unique Patterns in ECC That idea-factory Does NOT Have

**A. Continuous Learning / Session Self-Improvement**
- `skills/continuous-learning-v2/` with `observe.sh` hooks on every PreToolUse and PostToolUse
- `stop:evaluate-session` hook extracts reusable patterns from every session automatically
- `/learn` and `/skill-create` commands generate skills from git history
- 이건 **self-improving system** — 하네스가 매 세션 후 더 똑똑해짐

**B. Tiered Hook Modes (minimal / standard / strict)**
- `scripts/hooks/run-with-flags.js` 가 모든 훅을 mode flag 로 gate
- 훅 완전 비활성화 없이 aggressiveness 조정 가능
- ECC 의 `hooks.json` 은 20+ named hooks (각자 `pre:bash:commit-quality` 같은 stable ID) — idea-factory 의 lean allow/deny 방식과 대비

**C. Cost Tracking Infrastructure**
- `stop:cost-tracker` 훅이 세션당 token/cost 메트릭 로깅
- `post:bash:command-log-cost` 가 모든 Bash 툴 호출 + timestamp 로깅
- `ecc-tools-cost-audit` skill 은 cost-aware LLM 파이프라인 설계용
- idea-factory 는 cost 가시성 **전혀 없음**

**D. Session State Persistence Across Compactions**
- `PreCompact` 훅이 context compaction 전에 상태 저장
- `SessionStart` 훅이 새 세션에서 이전 컨텍스트 복원
- `stop:session-end` 가 각 응답 후 세션 상태 persist
- idea-factory 는 context window 경계에서 모든 컨텍스트 loss; persistence layer 없음

**E. GAN Architecture Agents**
- `agents/gan-evaluator.md`, `agents/gan-generator.md`, `agents/gan-planner.md`
- agent level 에서 명시적 GAN-inspired generator/evaluator 분리 (리뷰 프레이밍만이 아님)
- idea-factory 는 GAN 원칙을 리뷰어 프레이밍에 적용하지만 dedicated GAN-role agents 없음

**F. Config Protection Hook**
- `pre:config-protection` 이 에이전트가 linter/formatter 설정 (eslint, tsconfig 등) 약화시키는 것 차단
- 에이전트를 "설정 낮추기" 대신 "코드 고치기" 로 유도
- idea-factory 에 equivalent 없음 — 에이전트가 타입 에러 회피 위해 tsconfig 조용히 완화할 수 있음

**G. Design Quality Drift Detection**
- `post:edit:design-quality-check` 가 프론트엔드 수정이 "generic template-looking UI" 쪽으로 drift 할 때 경고
- idea-factory 는 제품 drift 용 essence.md 개념 있지만 UI quality signal 훅 레벨 없음

**H. MCP Health Check**
- `pre:mcp-health-check` 가 MCP 서버 살아있는지 호출 전 검증; unhealthy 서버 마킹
- `PostToolUseFailure` 훅이 실패한 MCP 호출 추적하고 재연결 시도
- idea-factory 는 MCP resilience layer 없음

**I. Governance Capture**
- `pre:governance-capture` + `post:governance-capture` 가 시크릿, 정책 위반, 승인 요청 캡처
- `ECC_GOVERNANCE_CAPTURE=1` 로 활성화 — opt-in enterprise 기능
- idea-factory 는 deny-list 있지만 뭐가 차단됐고 왜인지 audit trail 없음

**J. Batch Format+Typecheck at Stop (per-edit 아님)**
- `stop:format-typecheck` 가 응답 동안 편집된 JS/TS 파일 전부 누적, 그 후 Stop 에서 한 번만 Biome/Prettier + tsc 실행
- 매 편집 후 포맷 체크 실행 피함 (비용 + 노이즈)
- idea-factory 의 훅은 per-event, batched 아님

**K. Cross-Harness Support**
- Codex (`.codex/`), Cursor (`.cursor/hooks/`), CodeBuddy (`.codebuddy/`), OpenCode 를 위한 네이티브 config adapters
- ECC 는 Claude Code 밖에서도 동작; idea-factory 는 Claude Code 전용

**L. Rust Control Plane (ECC 2.0 Alpha)**
- `ecc2/` — Rust daemon with `dashboard`, `start`, `sessions`, `status`, `stop`, `resume` commands
- 다중 동시 에이전트 세션 관리 인프라
- idea-factory 는 세션 관리 인프라 없음

**M. Selective Install Architecture**
- `scripts/install-plan.js` + `scripts/install-apply.js` — manifest-driven, 필요한 것만 설치
- SQLite state store 가 설치된 컴포넌트 추적, incremental update 가능
- idea-factory 는 single `install.sh` bash 스크립트, 컴포넌트 선택 없음

---

## 4. Overlap with idea-factory

| ECC Asset | idea-factory Equivalent | Who's Ahead |
|-----------|------------------------|-------------|
| `agents/code-reviewer.md` | `templates/agents/` (PM, Dev, Designer) | Tied — different scope |
| `agents/gan-evaluator.md` / `gan-generator.md` | 4-reviewer gate with adversarial framing | **idea-factory** — 제품 맥락에서 원칙을 더 잘 적용 |
| Two-pass defect-then-score | Two-pass evaluation in HARNESS-GUIDE.md | **idea-factory** — 패턴만이 아니라 증거와 함께 문서화 |
| `agents/security-reviewer.md` | deny-list in `settings.json` | **ECC** — blocklist 뿐 아니라 전체 security review agent |
| `commands/feature-development.md` | SKILL.md execution flow | **ECC** — 더 풍부한 command vocabulary |
| `hooks/hooks.json` (session persistence) | No equivalent | **ECC** — 명백한 승자 |
| `skills/continuous-learning-v2/` | No equivalent | **ECC** — 명백한 승자 |
| `skills/market-research/` | analyst agent in SKILL.md | Tied — 다른 depth |
| Playwright E2E (`skills/e2e-testing/`) | Playwright MCP for qa-tester | **idea-factory** — 라이브 브라우저 QA 가 제품 게이트에 통합 |
| `skills/tdd-workflow/` | No TDD phase | **ECC** |
| Fix-loop circuit breaker | SKILL.md circuit breaker pattern | **idea-factory** — 있음, ECC 는 prominently 없음 |
| essence.md / North Star | No equivalent | **idea-factory** — 독특하고 강함 |
| Phase handoff documents (MVP/Harden/Ship) | No equivalent | **idea-factory** — 독특 |
| `rules/` (always-on guidelines) | CLAUDE.md template | **ECC** — rules as separate files 가 더 깨끗한 분리 |

---

## 5. Gaps idea-factory Should Address

**HIGH — Session Persistence / PreCompact State Save**
ECC 의 `PreCompact` + `SessionStart` 훅이 context 경계에서 에이전트 상태 save/restore. idea-factory 의 multi-phase workflow (MVP → Harden → Ship) 이 바로 이 use case 에 가장 필요. 현재 장시간 빌드가 context limit 치면 모든 phase state loss. **Concrete recommendation**: `pre:compact` 훅이 phase state, 현재 story status, essence.md snapshot 을 `.omc/state/` 파일에 기록; `session:start` 훅이 읽어옴.

**HIGH — Cost Tracking Hook**
어떤 CEO 도 idea-factory 돌리고 $40 토큰 태운 걸 경고 없이 발견하고 싶지 않음. ECC 의 `stop:cost-tracker` 는 가벼운 Stop 훅. **Concrete recommendation**: `templates/hooks/` 에 `stop:cost-summary` 훅 추가, 세션 transcript 읽고 총 input/output 토큰 + 추정 비용 출력. 한 파일, high value.

**HIGH — Config Protection Hook**
에이전트가 TypeScript 에러 해결하려고 `tsconfig.json` 약화시키거나 ESLint 룰 비활성화하는 것 — 멀티시간 MVP 빌드에서 실제 failure mode. ECC 의 `pre:config-protection` 이 config 파일 쓰기 차단하고 코드 fix 로 redirect. **Concrete recommendation**: 선택이 아니라 표준 가드로 `templates/hooks/` 에 추가.

**MED — Batch Format+Typecheck at Stop**
매 편집 후 linter 실행은 비용 + 지연. ECC 의 accumulator + Stop 패턴이 더 똑똑. **Concrete recommendation**: idea-factory 의 per-edit quality check 를 session Stop 에서 한 번 실행되는 accumulator 로 교체.

**MED — Tiered Hook Modes (minimal/standard/strict)**
idea-factory 훅은 binary (on/off). ECC 의 mode flag 시스템은 advanced 사용자가 훅 파일 해킹 없이 strictness 조정 가능. **Concrete recommendation**: `templates/settings.json` 에 `MODE` env 변수 추가, 훅 스크립트가 실행 전 체크. 낮은 구현 비용, 높은 UX 가치.

**MED — Continuous Learning / `/skill-create`**
ECC 의 Stop 훅이 세션 평가해서 재사용 가능 패턴 추출. idea-factory 는 제품 패턴용으로 할 수 있음: "어떤 종류 아이디어가 최고의 MVP 를 생성하나?", "어떤 스택 선택이 가장 많은 재작업을 일으켰나?" **Concrete recommendation**: 가벼운 `stop:retrospective` 훅, 세션 요약 한 문단 `.omc/logs/` 에 기록 — 전체 AI 호출 아니라 structured notes.

**LOW — Desktop Notification at Stop**
ECC 가 에이전트 응답 끝날 때 macOS/WSL desktop 알림. idea-factory 는 긴 autonomous loop — MVP gate 완료 시 알림 유용. `templates/settings.json` 에 low-effort 추가.

**LOW — Selective Install**
ECC 의 manifest-driven install 은 idea-factory 현재 scope 엔 과함. v8 에 설계 고려 가치. 현재 single `install.sh` 는 idea-factory 가 multiple skills (start-company, continue-company, ship-company 등) 로 커지면 문제.

---

## 6. Anti-Patterns to Avoid

**Kitchen-sink bloat.** 1,947 파일, 181 skills, 47 agents — 대부분 서로 무관 (visa-doc-translate, videodb, x-api, fal-ai-media, investor-outreach 가 공존). 이 모든 것을 동시에 쓸 coherent "user" 는 없음. ECC 는 grab-bag curator repo, 제품 아님. idea-factory 의 "한 workflow 를 잘하는" discipline 이 올바른 본능.

**Cross-harness dilution.** Codex, Cursor, OpenCode, CodeBuddy 동시 지원 = 어떤 하네스도 full treatment 못 받음. Cursor adapter 는 thin JS shim; Codex config 은 .toml 파일 몇 개. Depth 없는 breadth. idea-factory 는 core 가 bulletproof 될 때까지 Claude Code-first 유지해야.

**Opaque hook scripts.** ECC 의 Stop 훅은 minified single-line Node.js eval 문자열 (`hooks.json` Stop section 은 훅당 literally 2,000자 minified line). 읽을 수 없고 유지보수 불가능. idea-factory 의 깨끗한 훅 스크립트는 **진짜 장점**.

**Rust daemon scope creep (ECC 2.0 alpha).** `ecc2/` Rust control plane 은 usably 배포 안 됨. 인프라를 위한 인프라 — core workflow 가 solid 해지기 전에 daemon, sessions, dashboard 추가는 engineering distraction. idea-factory 는 이 패턴 저항해야.

**Vanity metrics in README.** "140K+ stars" 는 이 repo 에 대해 거의 확실히 부정확 (GitHub 가 훨씬 적게 보여줌). README 텍스트의 over-credentialing 이 신뢰 훼손. idea-factory 의 정직한 demo-first README 가 더 나음.

---

## 7. Philosophy Comparison

ECC 의 철학은 **"전부 수집하고 노출"** — 10+ 개월 개인 일상 사용 후 broad 배포용으로 패키징된 파워유저 툴킷. 타겟 사용자는 battle-tested 설정을 선별 채택하고 싶어하는 experienced developer. Opinionated workflow 없음; 카탈로그. idea-factory 의 철학은 정반대: **one opinionated workflow, no choices required, designed for a non-developer CEO**. ECC 는 철물점; idea-factory 는 조립식 주택. ECC 는 tooling infrastructure (hooks, session management, cost tracking, continuous learning) 에서 앞섬. idea-factory 는 workflow coherence, product philosophy (essence.md, MVP-first phases, defect-then-score gates), accessibility 에서 앞섬. 일반 하네스를 빌딩하는 개발자는 ECC 를 면밀히 연구해야. 일하는 MVP 를 원하는 founder 는 idea-factory 를 써야. idea-factory v8 의 리스크는 ECC 의 크기를 보고 inadequate 느끼고 → bloat. 올바른 수는 infrastructure 패턴 (session persistence, cost tracking, config protection) 을 선별 흡수하면서 ECC 가 완전히 결여한 workflow discipline 을 유지하는 것.

---

## 8. Recommendation

**즉시 흡수 (v7.2 / v8 prep)**:
- `pre:config-protection` 훅 — tsconfig/eslint 약화 방지, 한 스크립트
- `stop:cost-summary` 훅 — 세션당 토큰/비용 가시성
- Batch format+typecheck at Stop (per-edit 말고)

**v8 에 adaptation 으로 흡수**:
- Session 상태 persistence (`PreCompact` save + `SessionStart` restore) — idea-factory phase 모델에 맞게 적응
- Tiered hook modes (minimal/standard/strict) via `MODE` env 변수
- 가벼운 session retrospective log (ECC 의 full continuous-learning stack 아니라 structured notes 만)

**무시**:
- Cross-harness 지원 (Cursor/Codex adapters) — core 완료 전까지
- 181-skill 카탈로그 모델 — idea-factory focus 의 안티테제
- Rust control plane (ECC 2.0) — 조기
- Governance capture / enterprise controls — 잘못된 audience

**다르게 할 것**:
- ECC 는 제품 workflow 없음. essence.md, MVP-first phase gate, Playwright-integrated QA 제품 맥락 — 이게 idea-factory 의 진짜 강점. v8 은 ECC 스타일 breadth 로 교체가 아니라 이것들을 deepen 해야.
- ECC 훅 스크립트는 opaque (minified inline eval). idea-factory 는 품질 신호로 readable, well-commented 훅 스크립트 유지해야.
- ECC README 은 카탈로그. idea-factory 의 demo-first README (한 명령, 전체 출력, 실제 제품 이름) 가 더 compelling — 유지해야.

**정직한 판정**: ECC 는 scope 과 infrastructure engineering 에서 인상적. 제품 또는 workflow 로는 인상적이지 않음. idea-factory 와 다른 문제를 해결함. 위 세 개 infrastructure 패턴 (cost tracking, config protection, session persistence) 은 훔칠 가치 있음. 나머지는 모두 idea-factory 가 이미 더 잘 하는 것을 중복하거나 out of scope.
