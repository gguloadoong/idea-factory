# Field Report: trading-signal-bot ← idea-factory Contribution Plan

**Date**: 2026-04-11
**Source**: Deep-dive research session with architect + document-specialist agents
**Status**: Plan document. **No implementation.** To be scheduled separately when signal bot development has an open window.
**Target project**: https://github.com/gguloadoong/trading-signal-bot

---

## 배경

trading-signal-bot 은 Vercel Edge 에 배포되는 cron-based 트레이딩 신호 봇. 15분마다 5-모델 앙상블(DNA / WALL ST / SENSE / QUANT / SHARK)로 한/미 주식 + 크립토 시그널을 계산해 Discord 로 알림. 사용자가 **"idea-factory 의 개발환경 측면에서 도움줄 수 있는 게 있나"** (하네스, 문서화, 컨텍스트 degradation, 바이브코딩 고질병 개선) 라는 좁은 렌즈로 질문.

두 개의 병렬 리서치 에이전트가 심층 조사:
- **architect (Opus, 로컬)**: trading-signal-bot 실제 코드 읽고 harness/DX 관점 진단. 원본: `docs/research/2026-04-11-tsb-harness-architect.md`
- **document-specialist (외부)**: Claude Code 바이브코딩 고질병의 학계/업계 문헌 리서치. 원본: `docs/research/2026-04-11-tsb-harness-external.md`

---

## 핵심 발견 (교차 검증)

두 에이전트가 독립적으로 동의한 3가지:

1. **trading-signal-bot 은 "앱으로 위장한 파라미터 튜닝 코드베이스"** — 1116줄의 `_signal-engine.js` 가 매직넘버 튜닝 위주. idea-factory 의 타깃(앱 스캐폴딩)과 DX 리스크 프로파일이 근본적으로 다름.
2. **v7.1 `bypassPermissions + deny-list` 는 라이브 머니 봇에 부적합** — `vercel --prod`, `vercel env add`, `redis-cli FLUSHDB` 등이 전부 허용됨. deny-list 확장 + exit-0 audit-log 훅 필요.
3. **사용자의 v7→v7.1 교훈("blocking PreToolUse = 자율 루프 사망")이 외부 문헌 코퍼스 전체에서 가장 battle-tested 된 발견** — 이 레포 자체가 1차 증거.

---

## idea-factory 가 **지금 당장** 줄 수 있는 것 (5개)

### 1. CLAUDE.md (프로젝트 설명서) 📖
- **현재 상태**: trading-signal-bot 에 없음
- **역할**: Claude 가 지켜야 할 5-6가지 불변 규칙 (DNA 순수성, `_ta-core.js` 리팩토링 금지, 앙상블 count-based, ±10% 변경은 CEO 승인, 프로덕션 Redis 보호)
- **난이도**: 가장 쉬움. 파일 하나 추가 (~50줄, 80줄 제한 내)
- **충돌 리스크**: 0 (추가만)

### 2. CONTRACT.md FAQ (zombie 방지) 📋
- **현재 상태**: 없음
- **역할**: 과거 결정을 다음 세션이 "좋은 의도로" 되돌리는 것을 막는 FAQ. architect 리서치가 실제 코드에서 7개 구체 zombie 후보 발견:
  1. DNA 가 RSI/MACD 안 읽음 — 3-layer purity defense
  2. DNA 에 trailing stop 없음 — WALL ST 에 위임
  3. `score < 40` 매수 임계값 — MAJOR-3 노이즈 감축
  4. `SR_PROXIMITY_PCT 1.5` — MAJOR-6 타이트닝
  5. `SHARP_DROP_PCT -3` — Bug3 완화
  6. Python `models/` 보존 — 포팅 레퍼런스
  7. `_ta-core.js` 가 copy — Vercel Edge 의존성 제거
- **난이도**: 쉬움. 7개 Q&A 쓰면 끝
- **충돌 리스크**: 0

### 3. `.protected-files` (크라운 주얼 목록) 🔒
- **현재 상태**: 없음
- **역할**: 망가지면 큰일 나는 파일 리스트. 내용: `api/_signal-engine.js`, `api/_ta-core.js`, `api/_composite-scorer.js`, `analysis/dna-v2-training.json`, `api/dna-engine/**`
- **난이도**: 쉬움. 파일 이름 5개
- **충돌 리스크**: 0

### 4. `.claude/settings.json` (위험 명령 차단) 🚧
- **현재 상태**: 없음
- **역할**: v7.1 deny-list base + trading-bot 전용 확장 (`vercel --prod`, `vercel env add/rm`, `redis-cli FLUSHDB/FLUSHALL`)
- **난이도**: 쉬움. 짧은 JSON
- **충돌 리스크**: 낮음 — **단, 사전 확인 필요**: "평소 Claude Code 세션에서 `vercel --prod` 를 직접 실행하는 습관이 있나?" 있다면 deny-list 조정 필요

### 5. 2-Reviewer 검증 게이트 (architect + backtest-qa) 🕵️
- **현재 상태**: 없음
- **역할**: 파라미터 튜닝 세션이 self-praise 하는 걸 막기. 격리된 worktree 에서 **다른** Claude 세션이 독립 백테스트 실행 + adversarial defect-first 프레이밍 ("이 파라미터 변경이 overfit 하거나 프로덕션에서 깨질 이유를 모두 찾아라")
- **난이도**: 복잡. 여러 파일 + 스크립트 + agent definition
- **충돌 리스크**: 낮음 — opt-in only, 기존 워크플로우 강제 변경 아님
- **전제**: 4 번까지 완성 후에만 의미 있음

---

## idea-factory 에 **아직 없어서** 지금은 못 주는 것

(이건 v8 backlog 로 편입. `docs/plans/v8-backlog.md` 참조)

- **Exit-0 audit-log PreToolUse 훅** (v8 item 1.1) — 모든 Bash 커맨드를 차단 없이 로깅
- **Cron-bot 프로젝트 템플릿** (v8 item 5.2) — 현재 idea-factory 는 웹앱 가정
- **Numerical tuning harness primitive** (v8 item 5.1) — 파라미터 튜닝을 first-class workflow 로
- **Temporal leakage 도메인 lint** (v8 item 5.5) — SysTradeBench 의 `shift(-1)`, `iloc[-1]` 패턴 감지
- **Write-time secret leakage 스캐너** (v8 item 1.2) — 에이전트가 `console.log(apiKey)` 생성하는 것 방지

**이들이 idea-factory v8 에 완성되면 trading-signal-bot 이 첫 검증 사이트 (first validation site) 후보.**

---

## 실행 설계 원칙 (꼬임 방지)

signal bot 이 한창 개발 중이라는 제약을 플랜 전체에 관통:

1. **Zero-touch on existing files** — 새 파일 추가만. `_signal-engine.js`, `_ta-core.js` 등 절대 수정 금지
2. **Additive-only** — `.claude/`, `CLAUDE.md`, `CONTRACT.md`, `scripts/backtest-*.js` 전부 신규
3. **독립 브랜치 + 작은 PR** — 각 phase 가 별도 브랜치. signal bot 의 feat/fix 브랜치와 절대 겹치지 않음
4. **Reversible** — 모든 phase 는 `git revert` 1방으로 되돌릴 수 있어야 함
5. **단계적 채택 가능** — Phase A 만 해도 가치 있음. A→B→C→D 순차 강제 아님

---

## 4단계 Phase 계획

### 🟢 Phase A — Zero-Touch 문서 artifacts (가장 안전)
신규 파일만. 어떤 기존 파일도 건드리지 않음.

| 파일 | 내용 |
|---|---|
| `CLAUDE.md` | 50줄 스켈레톤. 5개 invariant + session checklist + CEO 승인 필요 목록 + fix-loop 서킷 브레이커 + 튜닝 프로토콜 |
| `CONTRACT.md` | 7개 zombie 후보 FAQ |
| `.project/essence.md` | "15분마다 신호 쏘는 Discord 봇. 학습은 보조. 절대 연구 프레임워크 아님." |
| `.project/decisions.md` | 숫자 우선 ADR 포맷. `MAJOR-3`, `MAJOR-6`, `Bug3` 를 과거 ADR 로 역문서화 |
| `.protected-files` | 5개 파일 리스트 |

**완료 정의**: `chore: add Claude Code documentation scaffolding` PR 1개.

**Phase A 만 해도 zombie 후보 7개 차단 + DNA 순수성 invariant 문서화 + 이후 세션들의 onboarding time 급감.**

### 🟢 Phase B — Harness 기본 (.claude/ 생성)
`.claude/` 디렉터리 현재 없음. 디렉터리 전체 신규.

| 파일 | 내용 |
|---|---|
| `.claude/settings.json` | v7.1 base + trading-bot 전용 deny-list 확장 |
| `.claude/hooks/check-claudemd-size.sh` | idea-factory 템플릿 그대로 |
| `.claude/hooks/check-quality.sh` | 선택. Stop 훅 |

**사전 확인 필요**: 
- `vercel --prod` 를 Claude Code 세션에서 자동 실행한 적 있나?
- `redis-cli FLUSHDB` 를 개발용으로 쓰나?

### 🟡 Phase C — 튜닝 워크플로우
| 파일 | 내용 |
|---|---|
| `scripts/backtest-against-signal-log.js` | Upstash `signal:log` 최근 N일 pull → 현재 엔진 리플레이 → winrate, FP rate, consensus distribution 출력. 한 번 작성 후 `.protected-files` 에 고정 |
| `.project/tuning-protocol.md` | 튜닝 세션 규칙 (한 번에 한 파라미터, 3번 실패 = STOP, evidence trailer 필수) |
| `.project/handoff-experiment.md.tmpl` | 튜닝 실험 handoff 템플릿 |
| `.project/quality-baseline.md` | **runtime 메트릭** 기준 (30일 winrate, FP rate 등). 현재 수치는 사용자 승인 후 확정 |

**핵심 가치**: "파라미터 변경 = 코드 변경 + 백테스트 증거 + ADR 엔트리" 를 강제. Ghost Bug + Evaluator Leniency + Fix-Loop Thrashing 동시 차단.

### 🟡 Phase D — 2-Reviewer Gate (튜닝 전용, opt-in)
| 파일 | 내용 |
|---|---|
| `scripts/tuning-review-gate.sh` | architect + backtest-qa 병렬 실행 |
| `.claude/agents/architect.md` | 50+ 줄 agent definition |
| `.claude/agents/backtest-qa.md` | 50+ 줄 agent definition |
| `scripts/create-tuning-pr.sh` (선택) | `_signal-engine.js` 수정 브랜치는 이 게이트 통과 후에만 PR 생성 |

**주의**: 모든 게이트는 opt-in. 강제 훅 아님. 튜닝 세션에서만 명시적으로 호출.

### 🔵 Phase E — idea-factory v8 쪽 작업 (병렬, signal bot 무영향)
signal bot 에 직접 적용하지 않고 idea-factory 쪽에 v8 기능 추가.

**참조**: `docs/plans/v8-backlog.md` items 1.1, 1.2, 5.1, 5.2, 5.5, 1.3

**이 작업들이 완성되면 trading-signal-bot 이 첫 프로덕션 검증 사이트** 후보.

---

## 충돌 회피 체크리스트 (각 Phase 시작 전)

### Phase A 시작 전
- [ ] trading-signal-bot 최신 main pull
- [ ] `CLAUDE.md`, `CONTRACT.md`, `.protected-files`, `.project/` 존재 확인 (현재 기준 없음)
- [ ] `gh pr list` 로 진행 중 PR 과 겹침 확인
- [ ] 별도 브랜치: `docs/claude-integration-phase-a`

### Phase B 시작 전
- [ ] `.claude/` 디렉터리 존재 재확인
- [ ] **중요**: `vercel --prod` 를 Claude Code 로 직접 실행 습관 있는지 사용자 질문
- [ ] `redis-cli` 개발/프로덕션 분리 확인

### Phase C 시작 전
- [ ] `scripts/backtest-*`, `scripts/tuning-*` 이름 충돌 확인
- [ ] `.project/` 기존 내용 확인
- [ ] 튜닝 프로토콜은 **opt-in** 명시
- [ ] `quality-baseline.md` 숫자는 **사용자 승인 후** 확정

### Phase D 시작 전
- [ ] `scripts/create-pr.sh` 충돌 체크 → 있으면 `create-tuning-pr.sh` 로 네임스페이스 분리
- [ ] `.claude/agents/` 기존 내용 확인
- [ ] 2-reviewer gate 는 opt-in only

---

## 명시적 제외

| 항목 | 제외 사유 |
|---|---|
| Playwright MCP qa-tester | UI 없음 |
| Phase Handoff Documents (verbatim) | 페이즈 없음. Phase C 의 tuning-experiment handoff 가 대체 |
| 6-Gate Deploy Consensus | Vercel 자동 배포, 사람 승인 게이트 불필요. Phase B 의 vercel deny + v8 1.1 audit log 로 교체 |
| 4-Reviewer Gate (critic + code-reviewer 포함) | 단일 파일 숫자 변경에 overkill. Phase D 의 2-reviewer 로 축소 |
| .githooks/pre-push stale review | 공식 리뷰 워크플로 없음 |
| 기존 파일 수정 전부 | blast radius ≥ 0 인 모든 작업 |

---

## 우선순위 요약

| 우선순위 | 항목 | 난이도 | 충돌 위험 |
|---|---|---|---|
| ⭐⭐⭐ | Phase A.1 CLAUDE.md | 쉬움 | 없음 |
| ⭐⭐⭐ | Phase A.2 CONTRACT.md (7 FAQ) | 쉬움 | 없음 |
| ⭐⭐⭐ | Phase A.5 .protected-files | 쉬움 | 없음 |
| ⭐⭐ | Phase B .claude/settings.json | 쉬움 | 확인 필요 |
| ⭐ | Phase D 2-reviewer gate | 복잡 | 낮음 |
| 별도 | Phase E v8 작업 | 큼 | 0 (idea-factory 쪽) |

**1, 2, 3 은 파일 3개 추가**라서 signal bot 개발에 전혀 방해 안 됨. 가장 안전하고 가장 가성비 좋음.

---

## 이 리포트의 리스크 (정직)

1. **Phase B 의 deny-list 는 생산성 트레이드오프 유발 가능**. `vercel --prod` 습관이 있다면 마찰. 완화: 사전 질문.
2. **Phase D 의 2-reviewer gate 는 "자율 튜닝" 을 느리게 함**. 의도된 효과 (rubber-stamp 방지) 지만 overhead 는 overhead.
3. **CLAUDE.md 와 CONTRACT.md 가 현실을 못 따라갈 위험**. 완화: `decisions.md` 지속 업데이트 + 월 1회 FAQ 감사.
4. **이 계획 자체가 틀릴 수 있음**. 첫 리포트가 "Fix-Loop Circuit Breaker SKIP" 이라고 한 걸 두 번째 리서치가 뒤집은 것처럼. 완화: Phase A 부터, 각 phase 성공 판정 기준 측정 후 진행.

---

## 다음 결정 지점

이 리포트는 **개발 시작 명령이 아닙니다**. 사용자가 나중에 시간 낼 때 reference 문서로 사용합니다.

가능한 경로:
1. **Phase A 만 확정**, 나머지는 "나중에"
2. **Phase E (idea-factory 쪽) 먼저** — signal bot 무영향
3. **v8 audit-log hook (1.1)** 을 idea-factory 내부에 프로토타입 후 trading-signal-bot 에 시범 적용
4. **그냥 보관**, 시간 낼 때 다시 읽기

---

## 참조

- Research archive: `docs/research/2026-04-11-tsb-harness-architect.md`
- Research archive: `docs/research/2026-04-11-tsb-harness-external.md`
- v8 backlog: `docs/plans/v8-backlog.md`
- v7 incident: `docs/field-reports/2026-04-11-v7-propagation-postmortem.md`
- trading-signal-bot: https://github.com/gguloadoong/trading-signal-bot
