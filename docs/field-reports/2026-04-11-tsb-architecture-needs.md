# trading-signal-bot — 아키텍처/하네스 장기 니즈 로드맵

**Date**: 2026-04-11
**Purpose**: trading-signal-bot 가 **장기적으로** 필요로 하는 아키텍처/하네스 레벨 개선사항을 trading-signal-bot 의 관점에서 정리. 사용자가 시간 날 때 검토해서 직접 우선순위를 결정할 수 있도록, **"뭐가 필요한가"** 를 먼저 말하고 **"idea-factory 가 언제 뭘 줄 수 있나"** 를 대응시킴.
**Companion document**: `docs/field-reports/2026-04-11-tsb-contribution-plan.md` (= **지금 당장** 할 수 있는 실행 계획). 이 문서는 **앞으로** 할 수 있는 것까지 포함한 큰 그림.

---

## TL;DR 체크리스트 (10개 니즈)

| # | 니즈 | 가치 | 시급도 | 현재 idea-factory 가 줄 수 있나? |
|---|---|---|---|---|
| 1 | **라이브 머니 런타임 안전** | 최고 | 고 | ⚠️ 부분 (deny-list 는 있음, audit log 는 v8) |
| 2 | **파라미터 튜닝 워크플로우** | 최고 | 고 | ❌ 없음 (v8 item 5.1) |
| 3 | **자동화된 Zombie 방지** | 높 | 고 | ⚠️ 부분 (CONTRACT FAQ 는 있음, AST 강제 는 v8) |
| 4 | **튜닝 Rubber-stamp 방지** | 최고 | 고 | ✅ 패턴 있음 (Fresh Context Isolation, 단 축소 필요) |
| 5 | **Fix-loop 서킷 브레이커 (코드 강제)** | 높 | 중 | ⚠️ 부분 (CLAUDE.md 산문만, 코드 강제는 v8) |
| 6 | **튜닝 세션 Context Degradation 방어** | 높 | 중 | ⚠️ 부분 (80줄 limit, handoff 는 cron 에 안 맞음) |
| 7 | **Temporal Leakage 도메인 감지** | 중 | 저 | ❌ 없음 (v8 item 5.5) |
| 8 | **Copied Code Drift 감지** | 중 | 저 | ❌ 없음 (v8 item 5.4) |
| 9 | **Cron-bot 프로젝트 템플릿** | 중 | 저 | ❌ 없음 (v8 item 5.2) |
| 10 | **Runtime 메트릭 Quality Ratchet** | 높 | 중 | ❌ 없음 (v8 item 5.3) |

**"가치"** = 이 니즈가 해결되지 않으면 얼마나 큰 사고가 날 수 있나.
**"시급도"** = 해결 지연이 얼마나 비용을 누적시키나 (high = 지금 매일 리스크 쌓임).

---

## 우선순위 가이드 (사용자 결정용)

내가 검토할 때의 **렌즈**:

- **니즈 1 + 니즈 4** → "프로덕션 사고 방지" — 이게 가장 큰 걱정이면 이 2개 먼저.
- **니즈 2 + 니즈 3** → "개발 생산성 + 회귀 방지" — 튜닝하면서 "왜 또 망가지지?" 가 반복되면 이 2개 먼저.
- **니즈 5 + 니즈 6** → "장기 세션 피로도" — Claude 와 오래 일하다 보면 답답함이 쌓이면 이 2개 먼저.
- **니즈 7 + 니즈 8 + 니즈 9 + 니즈 10** → "훨씬 나중" — 도메인 특화 고급 기능. 앞의 것들이 자리잡은 후에.

---

## 니즈 1: 라이브 머니 런타임 안전

### 문제
trading-signal-bot 은 15분마다 Discord 로 실제 신호를 쏘는 라이브 봇. Claude Code 세션에서 실수로 `vercel --prod`, `vercel env rm`, `redis-cli FLUSHDB` 같은 명령이 실행되면 **15분 내 라이브 사용자들에게 영향**. 현재 이런 명령은 전혀 차단되지 않음.

### 왜 중요
돈과 직결된 실수는 되돌릴 수 없음. `signal:positions` Redis 가 날아가면 모든 진행 중 신호가 증발. 잘못된 배포는 잘못된 신호로 이어짐.

### 현재 상태 (v7.1)
- ✅ `deny`-list 로 `rm -rf /`, `sudo *`, `.env*` 읽기 차단
- ❌ `vercel --prod`, `vercel env`, `redis-cli FLUSHDB` 는 허용
- ❌ audit trail 없음 — 사고 났을 때 "에이전트가 뭘 실행했나" 재구성 불가
- ❌ post-session 리뷰어 없음

### 단기 (지금 가능)
**Phase B (tsb-contribution-plan.md)** 의 trading-bot 전용 deny-list 확장:
```
"Bash(vercel --prod*)", "Bash(vercel env add*)", "Bash(vercel env rm*)",
"Bash(redis-cli FLUSHDB*)", "Bash(redis-cli FLUSHALL*)"
```
**확인 필요**: 평소 Claude Code 세션에서 `vercel --prod` 를 직접 실행하시나요? 있으시면 deny 대신 다른 방법 필요.

### 중기 (idea-factory v8 이후)
- **v8 item 1.1** — Exit-0 audit-log PreToolUse 훅. 모든 Bash 커맨드를 차단 없이 `.omc/audit/YYYY-MM-DD.jsonl` 에 기록. **이게 완성되면 tsb 가 첫 검증 사이트 후보.**
- **v8 item 1.3** — 프로젝트 타입별 deny-list extensions. `templates/settings-extensions/trading-bot.json` 같은 식으로 재사용 가능.
- **v8 item 1.4** — Post-session audit 리뷰어 에이전트. suspicious sequence 감지 (`vercel --prod` 직전에 `git stash` 같은 패턴).

### 장기 (v8 이후)
- Rollback 플레이북 자동화 — "이 커밋이 문제다" → 자동 revert + Vercel redeploy
- 실시간 신호 품질 이상 감지 → 자동 롤백

### 참조
- `docs/research/2026-04-11-tsb-harness-architect.md` §A.3
- `docs/plans/v8-backlog.md` Theme 1

---

## 니즈 2: 파라미터 튜닝 워크플로우 (가장 큰 gap)

### 문제
trading-signal-bot 의 작업의 80%는 `_signal-engine.js` 의 매직 넘버 튜닝 (`MOMENTUM_ENTRY_PCT: 3.0`, `SR_PROXIMITY_PCT: 1.5` 등). **이건 파일 diff 가 아니라 parameter delta 에 대한 작업**. idea-factory 는 이 패러다임을 first-class 로 지원하지 않음.

### 왜 중요
튜닝 세션은 **"파라미터 바꾸고 → 백테스트 → 개선?" 루프**. 이 루프가 체계화 안 되면:
- Ghost Bug: "좋아졌어요" 하는데 실제 백테스트는 안 돌림
- Evaluator Leniency: 자기가 튜닝한 파라미터를 자기가 평가 → rubber-stamp
- Fix-loop Thrashing: 같은 파라미터 3-4번 왔다갔다
- Zombie Reversion: 과거에 의도적으로 바꾼 임계값(MAJOR-3, MAJOR-6, Bug3) 을 "좋은 의도로" 되돌림

### 현재 상태 (v7.1)
**없음.** idea-factory 는 "work = file diff" 가정. 파라미터 튜닝을 위한 구조화된 workflow/primitive 없음.

### 단기 (지금 가능)
**Phase C (tsb-contribution-plan.md)** 의 수공예 버전:
- `scripts/backtest-against-signal-log.js` — Upstash `signal:log` 리플레이
- `.project/tuning-protocol.md` — 프로토콜 문서 (한 번에 한 파라미터, 3번 실패 = STOP, `Backtest:` trailer 필수)
- `.project/handoff-experiment.md.tmpl` — 튜닝 실험 handoff 템플릿
- **숫자 우선 ADR 포맷** 의 `decisions.md`

### 중기 (idea-factory v8 이후)
- **v8 item 5.1** — Numerical tuning harness primitive. 단기의 수공예를 idea-factory 가 템플릿으로 승격. 다른 ML/추천/pricing 프로젝트도 혜택.
- **v8 item 4.3** — Tried-and-failed session ledger. `"MOMENTUM_ENTRY_PCT 2.5 시도 3번째"` 를 다음 세션이 자동 감지.
- **v8 item 5.3** — Runtime 메트릭 Quality Ratchet. (니즈 10 참조)

### 장기 (v8 이후)
- 자동 하이퍼파라미터 검색 (Bayesian, grid) 과의 통합
- 파라미터 변경이 실시간으로 신호 품질에 미치는 영향 대시보드

### 참조
- `docs/research/2026-04-11-tsb-harness-architect.md` §A.1, §E.1
- `docs/plans/v8-backlog.md` Theme 5 item 5.1

---

## 니즈 3: 자동화된 Zombie 컴포넌트 방지

### 문제
architect 리서치가 trading-signal-bot 코드에서 **7개의 구체적 zombie 후보** 발견. 예: DNA 순수성 (RSI 안 읽음), trailing stop 부재 (WALL ST 에 위임), `score < 40` 임계값 (MAJOR-3), `_ta-core.js` 가 copy. 이것들은 주석으로만 이유가 기록되어 있어서, **다음 세션이 "좋은 의도로" 되돌릴 위험**.

### 왜 중요
각 zombie 는 "why we removed this" 가 문서화되지 않으면 반드시 재발. 세션 6개 걸치면 하나쯤은 다시 돌아옴.

### 현재 상태 (v7.1)
- ⚠️ CONTRACT.md FAQ 패턴 **존재** — 하지만 **에이전트 자발 체크 의존**. 읽고 무시하면 끝.
- ❌ 기계적 강제 없음
- ❌ 삭제된 심볼이 다시 추가되는지 git diff 레벨 감지 없음

### 단기 (지금 가능)
**Phase A (tsb-contribution-plan.md)** 의 `CONTRACT.md` — architect 가 뽑아준 7개 FAQ 엔트리 추가:
1. 왜 DNA 는 RSI/MACD 안 읽나? (3-layer purity defense)
2. 왜 DNA 에 trailing stop 없나? (WALL ST 위임)
3. 왜 매수 임계값이 40 인가? (MAJOR-3)
4. 왜 SR_PROXIMITY 1.5? (MAJOR-6)
5. 왜 SHARP_DROP -3? (Bug3)
6. 왜 Python models/ 보존? (포팅 레퍼런스)
7. 왜 `_ta-core.js` 가 copy? (Vercel Edge 의존성)

### 중기 (idea-factory v8 이후)
- **v8 item 3.2** — AST-level CONTRACT enforcement (ast-grep). "이 함수 시그니처에 `taCache`, `fundingData` 파라미터 금지" 같은 걸 pre-commit 훅으로 강제.
- **v8 item 3.3** — Zombie resurrection git-diff 훅. 과거 삭제된 심볼이 재추가되면 경고.
- **v8 item 3.4** — `.protected-files` YAML 업그레이드 (메타데이터 + trigger rule).

### 장기 (v8 이후)
- "invariant test" — 각 CONTRACT 엔트리에 대응하는 자동 테스트

### 참조
- `docs/research/2026-04-11-tsb-harness-architect.md` §B.2 (7개 zombie 리스트)
- `docs/plans/v8-backlog.md` Theme 3

---

## 니즈 4: 튜닝 세션 Rubber-stamp 방지 (단일 최강 레버리지)

### 문제
두 리서치 에이전트 모두 **"파라미터 튜닝 자기평가는 본질적으로 깨진 피드백 루프"** 라고 판정. "내가 튜닝한 모델이 내 백테스트에서 잘 나옴" 은 **default 실패 모드**. 외부 문헌 전체가 동의 (Anthropic primary, NUS Beyond Consensus, Epsilla).

### 왜 중요
이게 차단되면 다른 실패 모드들의 80% 가 같이 잡힘. 이게 차단 안 되면 다른 모든 방어책이 서서히 무너짐.

### 현재 상태 (v7.1)
- ✅ **Fresh Context Isolation** 패턴 존재 (worktree 격리 리뷰어). HARNESS-GUIDE.md §89-147.
- ✅ **Two-Pass 평가** 패턴 존재 (defect hunt → score). HARNESS-GUIDE.md §Two-Pass Evaluation.
- ❌ 하지만 **4-reviewer gate 는 파라미터 변경에 overkill** — 단일 파일 숫자 변경에 architect + critic + code-reviewer + qa-tester(Playwright) 다 필요 없음.
- ❌ **2-reviewer gate (architect + backtest-qa) preset 은 아직 없음**.

### 단기 (지금 가능)
**Phase D (tsb-contribution-plan.md)** — 수공예 2-reviewer gate:
- `scripts/tuning-review-gate.sh` — architect (Opus, 구조/불변) + backtest-qa (Sonnet, 실데이터 리플레이) 병렬 실행
- `.claude/agents/architect.md` + `.claude/agents/backtest-qa.md` — 50줄 agent definition
- **opt-in only** — 튜닝 세션에서 명시적으로 호출
- Backtest-qa 에게 adversarial 프레이밍 필수: "이 변경이 overfit 하거나 프로덕션에서 깨질 이유를 **모두** 찾아라"

### 중기 (idea-factory v8 이후)
- **v8 item 6.1** — Rule-driven reviewer gate sizing. 파일 패턴 기반 리뷰어 동적 선택. `_signal-engine.js` 수정 → 자동으로 2-reviewer 게이트.
- **v8 item 6.2** — `numeric-tuning.yml` preset 을 idea-factory 에 첫 등재.

### 장기
- Cross-model gate (Codex + Gemini) 를 파라미터 튜닝에 적용

### 참조
- `docs/research/2026-04-11-tsb-harness-architect.md` §A.4 (4→2 축소 근거)
- `docs/research/2026-04-11-tsb-harness-external.md` Part 2 Failure Mode 2, 8
- `docs/plans/v8-backlog.md` Theme 6

---

## 니즈 5: Fix-loop 서킷 브레이커 (코드 강제)

### 문제
"같은 실패 3번 = 멈춤" 규칙은 v7.1 에서 CLAUDE.md 의 **산문 규칙** 으로만 존재. 외부 리서치(Khare decay curve, Jaroslawicz 2025) 가 확인한 바로는 메시지 5-6 이후 산문 규칙 준수율 20-60% 로 붕괴. 튜닝 루프는 thrashing 의 #1 발생지.

### 현재 상태 (v7.1)
- ⚠️ CLAUDE.md 산문 규칙 있음 — 약함
- ❌ 코드로 강제되는 메커니즘 없음

### 단기 (지금 가능)
- **Phase A (tsb-contribution-plan.md)** 의 CLAUDE.md 에 fix-loop 섹션 추가 (산문이지만 없는 것보단 나음)
- **Phase C** 의 `decisions.md` 에 각 실패 시도 기록 → 다음 세션이 읽기 의무

### 중기 (idea-factory v8 이후)
- **v8 item 3.1** — Fix-loop 3-attempt 코드 강제. Stop 훅 또는 PostToolUse 가 최근 N 커맨드/에디트 비교, near-identical repeat 감지 시 hard stop.
- **v8 item 4.3** — Tried-and-failed ledger 와 통합.

### 참조
- `docs/research/2026-04-11-tsb-harness-external.md` Part 2 Failure Mode 6, Part 5 Gap 1
- `docs/plans/v8-backlog.md` Theme 3 item 3.1

---

## 니즈 6: 튜닝 세션 Context Degradation 방어

### 문제
긴 튜닝 세션에서 Claude 가 (a) DNA 순수성 규칙 망각, (b) `_ta-core.js` 가 copy 임을 망각하고 리팩토링, (c) consensus 가 count-based 임을 망각하고 가중치 추가, (d) 이미 reject 한 값 재시도 — 같은 증상들이 예상됨.

### 현재 상태 (v7.1)
- ✅ CLAUDE.md 80줄 limit (PostToolUse 훅)
- ✅ Phase handoff documents 패턴 — **단, trading-signal-bot 은 페이즈 없음 (연속 cron)**. 그대로는 안 맞음.
- ❌ 세션 중반 rule re-injection 없음
- ❌ 실패 시도 ledger 없음

### 단기 (지금 가능)
- **Phase A** 의 50줄 CLAUDE.md (핵심 invariant 앵커)
- **Phase C** 의 **tuning experiment handoff** (Phase handoff 의 cron 적응형. 한 실험 = 한 handoff 파일)
- **Phase C** 의 숫자 우선 `decisions.md` (검색 경로 역사)

### 중기 (idea-factory v8 이후)
- **v8 item 4.1** — Instruction compliance decay 카운터 + rule re-injection. 메시지 5-6 마다 critical invariant 를 `<system-reminder>` 로 재주입.
- **v8 item 4.3** — Tried-and-failed ledger.
- **v8 item 4.2** — Auto-compact loss validation (handoff 문서가 실제로 복원 가능한지 테스트).

### 참조
- `docs/research/2026-04-11-tsb-harness-architect.md` §C
- `docs/plans/v8-backlog.md` Theme 4

---

## 니즈 7: Temporal Leakage 도메인 감지 (학계 근거 있음)

### 문제
SysTradeBench (arxiv 2604.04812) 가 LLM 생성 트레이딩 코드에서 `df.shift(-1)`, `iloc[-1]`, unseeded `random` 같은 **look-ahead bias 버그** 를 정량 측정. 백테스트는 잘 나오는데 라이브에선 재현 안 되는 고전적 원인.

### 왜 중요
temporal leakage 버그는 code review 가 놓치기 쉽고, 백테스트 결과가 미래 데이터를 몰래 쓰는 거라 **라이브 성능이 백테스트의 절반 이하로 떨어지는** 경우가 흔함.

### 현재 상태 (v7.1)
- ❌ 없음. idea-factory 는 도메인 특화 lint 가 전혀 없음.

### 단기 (지금 가능)
- 수동: code review 시 `shift`, `iloc[-`, `random()` 검색 체크리스트화

### 중기 (idea-factory v8 이후)
- **v8 item 5.5** — Temporal leakage lint. ast-grep 패턴 모음을 `templates/lints/temporal-leakage/` 에. 트레이딩/시계열 프로젝트에 적용.

### 장기
- 백테스트 determinism 검증 (SHA256 strategy-card freeze + 15% divergence threshold, SysTradeBench 제안)

### 참조
- `docs/research/2026-04-11-tsb-harness-external.md` Part 4, Part 5 Gap 5
- `docs/plans/v8-backlog.md` Theme 5 item 5.5

---

## 니즈 8: Copied Code Drift 감지

### 문제
`api/_ta-core.js` (589줄) 는 market-dashboard-v5 의 `taCalculator.js` 에서 **verbatim 복사**. README.md:15 에 명시. 상류가 수정되면 drift 발생해도 감지 방법 없음. 에이전트가 "개선" 시도하면 drift 악화.

### 왜 중요
중요도는 중간 — 지금 당장 라이브 리스크는 아니지만, 장기적으로 TA 계산 로직이 상류와 divergence 하면 버그 원인 추적 어려워짐.

### 현재 상태 (v7.1)
- ❌ 없음. idea-factory 에 "이 파일은 copy 다" 개념 자체가 없음.

### 단기 (지금 가능)
- **Phase A** 의 `CLAUDE.md` invariant: "`_ta-core.js` 는 verbatim copy, 리팩토링 금지"
- **Phase A** 의 `CONTRACT.md` FAQ 엔트리: "왜 `_ta-core.js` 가 copy?"

### 중기 (idea-factory v8 이후)
- **v8 item 5.4** — `COPIED-FROM.md` 패턴. 각 copy 파일에 `{upstream_repo, upstream_path, upstream_commit, copied_at, sync_policy}` 기록 + CI diff 체크.

### 참조
- `docs/research/2026-04-11-tsb-harness-architect.md` §E.7
- `docs/plans/v8-backlog.md` Theme 5 item 5.4

---

## 니즈 9: Cron-bot 프로젝트 템플릿

### 문제
idea-factory 의 `start-company` 는 암묵적으로 **"웹앱 + UI + Playwright"** 가정. cron 봇/데이터 처리 봇 같은 **UI 없는 서비스** 에는 (a) Playwright 테스트 0 기여, (b) phase handoff 패턴 안 맞음, (c) runtime 메트릭 수집 전용 hook 없음, (d) rollback 스크립트 템플릿 없음 등 fit 불량.

### 현재 상태 (v7.1)
- ❌ 없음. 템플릿이 단일 변종.

### 중기 (idea-factory v8 이후)
- **v8 item 5.2** — `templates/cron-bot/` 변종. Playwright 빠지고, audit log + backtest harness + runtime metric collector + rollback 스크립트 추가.
- **v8 item 1.3** 와 통합 — cron-bot 전용 deny-list extension (`vercel --prod`, `redis-cli FLUSH*`).

### 참조
- `docs/research/2026-04-11-tsb-harness-architect.md` §E.6
- `docs/plans/v8-backlog.md` Theme 5 item 5.2

---

## 니즈 10: Runtime 메트릭 Quality Ratchet

### 문제
idea-factory 의 Quality Ratchet 은 **commit-time** 메트릭 가정 (bundle size, test count, lint errors). 하지만 trading-signal-bot 의 진짜 품질 신호는 **runtime** 메트릭 — 30일 winrate, false-positive rate, consensus count distribution, zero-consensus day 빈도. 이런 건 Redis/Upstash 에서 pull 해야 함.

### 왜 중요
commit-time 지표만 보면 "코드는 깨끗한데 신호 성능은 망함" 을 감지 못함. 트레이딩 봇은 코드 품질보다 runtime 품질이 중요.

### 현재 상태 (v7.1)
- ✅ Quality Ratchet 패턴 있음 (commit-time)
- ❌ runtime 메트릭 variant 없음

### 단기 (지금 가능)
- **Phase C** 의 `.project/quality-baseline.md` — runtime 메트릭을 수공예로 기록 (사용자 승인 후 확정)
- **Phase C** 의 `scripts/backtest-against-signal-log.js` — runtime 메트릭 pull 스크립트

### 중기 (idea-factory v8 이후)
- **v8 item 5.3** — Runtime 메트릭 Quality Ratchet variant. `templates/scripts/runtime-ratchet.sh` — state store pull, 시간 윈도우 비교, 회귀 감지 시 PR 머지 block.

### 참조
- `docs/research/2026-04-11-tsb-harness-architect.md` §E.4
- `docs/plans/v8-backlog.md` Theme 5 item 5.3

---

## 추천 진행 순서 (의존성 기반)

```
        ┌─ 니즈 1 (런타임 안전) ─────┐
        │                          │
        ├─ 니즈 4 (rubber-stamp) ───┤
        │                          │
  START ─┼─ 니즈 3 (zombie) ─────────┼──> 니즈 2 (튜닝 워크플로우) ─> 니즈 10 (runtime ratchet)
        │                          │           │
        ├─ 니즈 6 (context) ────────┘           │
        │                                      │
        └─ 니즈 5 (fix-loop) ───────────────────┘
                                               │
                                               └──> 니즈 7, 8, 9 (나머지)
```

### Wave 1 (작은 것부터, signal bot 무영향)
- **니즈 3** (CONTRACT.md FAQ 7개) — Phase A 의 파일 1개
- **니즈 6** (CLAUDE.md 50줄) — Phase A 의 파일 1개
- **니즈 5** (CLAUDE.md 의 fix-loop 섹션) — 니즈 6 과 통합
- **니즈 8** (copied file invariant) — 니즈 6 과 통합

👉 **Wave 1 은 파일 3-4 개 추가, 기존 파일 0개 수정.** 가장 안전.

### Wave 2 (보호 장치)
- **니즈 1** (deny-list 확장) — Phase B, 사전 확인 필요
- **니즈 4** (2-reviewer gate 수공예) — Phase D, opt-in

### Wave 3 (튜닝 infra)
- **니즈 2** (튜닝 워크플로우) — Phase C, `scripts/backtest-against-signal-log.js` 가 핵심
- **니즈 10** (runtime quality baseline) — 니즈 2 와 자연 통합

### Wave 4 (v8 완성 기다림)
- **니즈 7, 8, 9** — idea-factory v8 의 관련 item 이 릴리스되면 적용

---

## 결정 체크포인트 (사용자가 검토 후 내려야 할 결정들)

1. **니즈 1 의 Phase B deny-list 추가** 전에:
   - [ ] Claude Code 세션에서 `vercel --prod` 를 직접 실행하는 습관 있나? → 있다면 deny 대신 audit log 로 기다려야 할 수도
   - [ ] `redis-cli FLUSHDB` 를 개발 환경 리셋용으로 쓰나? → 있다면 프로덕션 URL 구분 필요

2. **니즈 2 의 Phase C `backtest-against-signal-log.js`** 를 만들 때:
   - [ ] 현재 `signal:log` Redis 키 포맷 확정되어 있나?
   - [ ] 백테스트가 참조할 "올바른 answer" 는 뭔가? (profit? 사용자 만족? 단순 winrate?)
   - [ ] `quality-baseline.md` 의 초기 수치는 어떻게 측정할지?

3. **니즈 4 의 2-reviewer gate 를 opt-in 으로 만들지 mandatory 로 만들지**:
   - [ ] 처음엔 opt-in 권장 (마찰 최소화), 사용 경험 쌓이면 `_signal-engine.js` 만 mandatory

4. **전체 순서**: Wave 1 만 먼저 할지, 1-2-3 순차 진행할지, 아니면 바로 v8 (Wave 4) 기다릴지 — 가치 vs. 시간 tradeoff

---

## 이 문서의 한계 (정직)

- **가치/시급도 평가는 나의 추정**. 실제 운영 경험 없이 외부 리서치 + 코드 읽기로만 매김. 실제 사용자 경험이 다르면 우선순위 재조정 필요.
- **v8 item 들은 아직 구현 안 됐음**. "언제" 가 모호 — backlog 순서에 따라 몇 주 ~ 몇 달. 긴급하면 v8 안에서 개별 item 선행 가능.
- **각 니즈를 독립적으로 가치 있게 설계**. 하지만 실제로는 서로 강화함 (예: 니즈 1 audit log + 니즈 4 2-reviewer gate = 훨씬 강한 방어).
- **첫 리포트(간단 요약)가 틀렸던 것처럼 이 계획도 일부 틀릴 수 있음**. Fix-loop breaker 를 처음엔 "SKIP" 이라고 한 것처럼. 실제 적용 중 발견되는 새 정보가 있으면 문서 업데이트 필요 (`field-reports/` 에 새 파일 추가 방식).

---

## 참조 문서

- 실행 계획 (즉시 할 것): `docs/field-reports/2026-04-11-tsb-contribution-plan.md`
- 원본 리서치 (architect): `docs/research/2026-04-11-tsb-harness-architect.md`
- 원본 리서치 (외부 문헌): `docs/research/2026-04-11-tsb-harness-external.md`
- v7 회귀 postmortem: `docs/field-reports/2026-04-11-v7-propagation-postmortem.md`
- idea-factory v8 백로그: `docs/plans/v8-backlog.md`
- target 프로젝트: https://github.com/gguloadoong/trading-signal-bot
