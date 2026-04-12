# idea-factory v8 Backlog

> **Living document.** Items are added as field learnings accumulate.
> Last updated: 2026-04-11 (initial creation from trading-signal-bot deep-dive research)

---

## 이 문서의 목적

이 백로그는 idea-factory 의 **자기인식 문서** 입니다. 실제 프로젝트에 idea-factory 를 적용하면서 발견된 **"있어야 하는데 없는 것들"** 을 누적 기록하고, 다음 메이저 버전(v8)의 방향을 설계하기 위한 근거로 씁니다.

v7.1 까지의 학습 경로:
- **v5** (2026-03): MVP-First + Ralph state machine
- **v6 / v6.1** (2026-04-02): Harness engineering overhaul
- **v7** (2026-04-04): market-dashboard-v5 에서 11개 battle-tested 패턴 흡수
- **v7.1** (2026-04-11): PreToolUse 훅 회귀 hotfix + 교훈 문서화
- **v8** (미정): 이 백로그 항목들을 선택적으로 반영

---

## Learning Layer (이 백로그의 부모 시스템)

v7.1 까지 idea-factory 는 자체 학습을 **체계적으로 기록하지 않았습니다.** 변화는 `HARNESS-GUIDE.md` Changelog (사후), GitHub Issues (수동), git log (raw) 에만 분산. 이번 v7→v7.1 회귀와 trading-signal-bot 조사에서 이 gap 이 명시적으로 드러났고, 그 수정으로 다음 3-layer 구조를 도입합니다:

```
docs/
├── plans/              ← 미래 방향 계획 (이 백로그가 여기)
│   └── v8-backlog.md
├── research/           ← 리서치 아티팩트 원본 보관 (에이전트 리포트 등)
└── field-reports/      ← 실제 프로젝트 적용 시 배운 것들 (사건 postmortem, 기여 계획 등)
```

**원칙:**
- **append-only**: 새 발견은 추가, 기존 항목은 수정하기보다 상태 업데이트 (todo → in-progress → done)
- **evidence-first**: 각 항목은 어디서 온 발견인지 출처 명시 (field-reports 또는 research 링크)
- **실행 가능성 보장**: 너무 추상적이면 별도 design doc 으로 분리

---

## 우선순위 가이드

| 레벨 | 기준 | 예 |
|---|---|---|
| **HIGH** | 영향 범위 큼 + 다른 항목 unblock + 증거 강함 | 1.1 exit-0 audit log |
| **MED** | 단일 영역 개선 + 증거 있음 | 3.1 fix-loop 코드 강제 |
| **LOW** | 니치 도메인 또는 구현 어려움 | 5.5 temporal leakage lint |

각 항목의 상태:
- `todo` — 백로그에 있음, 착수 전
- `in-design` — 설계 문서 작성 중
- `in-progress` — 구현 중
- `done` — 릴리스됨
- `deferred` — 일정 이후로 미룸 (사유 명시)

---

# Theme 1: Runtime Safety (post v7.1)

v7.1 의 `defaultMode: bypassPermissions` + narrow deny-list 는 무마찰 자율 실행에 올바른 floor 이지만, **실제 세계 비용이 걸린 프로젝트** (live trading, production deploy, 결제, 라이브 메시지, DB write) 에는 천장이 너무 낮음. trading-signal-bot 조사에서 이 gap 이 가장 크게 드러남.

### 1.1 Exit-0 audit-log PreToolUse hook [HIGH / Large]

**문제**: v7 의 blocking PreToolUse 훅은 자율 루프를 마비시켰다 (v7.1 hotfix). 반대 극단인 "훅 전혀 없음" 도 위험 — 라이브 환경에서 에이전트가 실행한 커맨드를 사후 감사할 방법이 없음. v7.1 HARNESS-GUIDE 가 명시적으로 "exit 0 logging hook 은 out of scope" 라고 shelved 한 작업.

**증거**: 
- `docs/research/2026-04-11-tsb-harness-architect.md` §A.3 — "trading-signal-bot 은 `vercel --prod`, `vercel env rm`, `redis-cli FLUSHDB` 가 전부 허용됨. audit trail 없음."
- `skills/start-company/HARNESS-GUIDE.md` "Design Decision: Runtime Safety via deny-list (v7.1 revision)" 섹션 — v7.1 이 exit-0 advisory 훅을 future work 로 명시적으로 미룬 기록. v7 릴리스 커밋 `e61f0af` 와 v7.1 hotfix 커밋 `546f24c` 참조.

**구현** (2026-04-11, issue #4):
- `templates/hooks/check-audit.sh` — PreToolUse Bash 훅. `trap 'exit 0' ERR EXIT` + 모든 외부 호출에 fallback + 명시적 `exit 0`. **exit non-zero 경로 없음**.
- `.claude/audit/YYYY-MM-DD.jsonl` 에 `{ts, session, matcher, tags, cmd}` JSONL append
- CAREFUL 패턴 태그 (라벨만, 차단 아님): `deploy` (vercel --prod/env), `redis-flush` (FLUSHDB/FLUSHALL), `npm-install`, `git-destructive` (force push/hard reset), `rm-rf`
- `templates/settings.json` 의 PreToolUse Bash matcher 에 등록 (timeout 3000ms)
- `HARNESS-GUIDE.md` Runtime Safety 섹션에 v8.1.1 블록 추가, v7 blocking 훅과의 대비 명시 (재발 방지)

**의존성**: 없음. 독립적으로 완결. 1.4 (post-session 리뷰어) unblock.
**첫 검증 사이트 후보**: trading-signal-bot (연동 계획은 `docs/field-reports/2026-04-11-tsb-contribution-plan.md` Phase E)
**상태**: `in-progress` (PR #5, 2026-04-11. 머지 시 `done` 로 업데이트 예정)

### 1.2 Write-time secret leakage scanner [MED / Small]

**문제**: v7.1 deny-list 는 `Read(.env*)`, `Read(**/credentials*)` 로 **읽기** 만 차단. 에이전트가 `console.log(apiKey)` 또는 `fetch(.../?api_key=${token})` 같은 **시크릿을 유출하는 코드를 생성** 하는 것은 막지 못함.

**증거**: `docs/research/2026-04-11-tsb-harness-external.md` Part 5 Gap 4 (BrightCoding 2025 practitioner warning, OWASP LLM #1 threat).

**스케치**: PostToolUse Write 훅 — 새로 작성된 파일에서 `console.log(.*(key|token|secret))`, `fetch(.*api_key=`, `throw new Error(.*process.env)` 등 패턴 매칭해서 경고 + audit log 기록.

**상태**: `todo`

### 1.3 Rule-driven deny-list extensions per project type [MED / Small]

**문제**: v7.1 deny-list 는 프로젝트 타입에 무관하게 고정. 라이브 머니 봇에는 `vercel --prod`, `redis-cli FLUSHDB` 추가 필요, 결제 프로젝트에는 `stripe *` 추가 등.

**증거**: `docs/research/2026-04-11-tsb-harness-architect.md` §A.3 (trading-signal-bot 전용 deny-list 목록).

**스케치**: `templates/settings.json` 을 base 로 두고, 프로젝트 타입별 extension json 을 `templates/settings-extensions/{web-app,cron-bot,payment,trading}.json` 에 저장. `start-company` 스캐폴드 시 선택 적용.

**의존성**: 5.2 (cron-bot 템플릿) 와 함께 하면 좋음.
**상태**: `todo`

### 1.4 Audit log post-session review agent [LOW / Medium]

**문제**: audit log (1.1) 가 존재해도 읽는 사람이 없으면 무의미.

**스케치**: 세션 종료 시 별도 에이전트가 그 날의 `.omc/audit/*.jsonl` 을 읽고 suspicious sequence (예: `vercel --prod` 직전에 `git stash`, 또는 `FLUSH` 직후 재시작) 패턴 감지 → 리포트 생성.

**의존성**: 1.1 필수 선행.
**상태**: `todo` (1.1 완성 후 시작)

---

# Theme 2: Learning Layer (이번 세션의 meta-gap)

v7.1 까지 idea-factory 는 자체 리서치/결정/학습을 체계적으로 기록하지 않았음. 이 이슈 자체가 이번 세션에서 사용자가 지적한 것.

### 2.1 `docs/research/` directory [HIGH / Trivial] ✅ DONE

**상태**: `done` (2026-04-11, 이 세션에서 생성)
**내용**: 외부 리서치 + 에이전트 심층 리포트 보관소. 첫 2개 아티팩트:
- `2026-04-11-tsb-harness-architect.md`
- `2026-04-11-tsb-harness-external.md`

### 2.2 `docs/field-reports/` directory [HIGH / Trivial] ✅ DONE

**상태**: `done` (2026-04-11, 이 세션에서 생성)
**내용**: 실제 프로젝트 적용 시 배운 것들. 첫 2개:
- `2026-04-11-v7-propagation-postmortem.md`
- `2026-04-11-tsb-contribution-plan.md`

### 2.3 `docs/plans/v8-backlog.md` [HIGH / Trivial] ✅ DONE

**상태**: `done` (이 파일 자체)

### 2.4 Session-end auto-capture mechanism [HIGH / Medium]

**문제**: 2.1-2.3 은 인프라만 만든 상태. 실제 작동하려면 **세션이 끝날 때** Claude 가 "이번 세션에서 학습한 것을 기록할까요?" 라고 자발적으로 제안하는 메커니즘이 필요. 그렇지 않으면 레이어가 있어도 채워지지 않음.

**스케치**: Stop hook (세션 종료) 이 트리거되면, 짧은 조건 체크 — "이번 세션이 research-heavy 였나? 새로운 gap 발견했나?" — yes 면 Claude 에게 summary + 저장 위치 제안. 과도한 트리거 방지 필요 (false positive 싫음).

**증거**: 이번 세션 자체. 만약 사용자가 "기록 안 하나?" 하고 물어보지 않았다면 두 개의 심층 리서치 리포트가 그냥 증발했을 것.

**의존성**: 없음.
**상태**: `todo`

### 2.5 Research artifact template [LOW / Small]

**문제**: `docs/research/` 에 저장되는 아티팩트들이 일관된 구조 없으면 검색/참조 어려움.

**스케치**: `templates/research-report.md.tmpl` — 제목/날짜/발주자/질문/출처/주요발견/gap/권고 섹션 고정. 에이전트 프롬프트에도 이 템플릿을 따르라고 명시.

**상태**: `todo`

---

# Theme 3: Enforcement (prose rules → code)

v7.1 은 많은 중요한 룰을 **CLAUDE.md 산문** 으로 기록. 하지만 Jaroslawicz et al. (2025) + Khare decay curve 가 보여주듯 긴 instruction 리스트는 메시지 5-6 이후 준수율 20-60% 로 붕괴. 핵심 룰은 **코드로 강제** 되어야 함.

### 3.1 Fix-loop 3-attempt code enforcement [HIGH / Medium]

**문제**: CLAUDE.md 의 "같은 실패 3번 = 멈춤" 룰은 프로즈 룰이라 instruction decay 의 영향을 그대로 받음. 특히 파라미터 튜닝 루프에서 thrashing 은 #1 실패 모드 (architect 리포트 확인).

**증거**: 
- `docs/research/2026-04-11-tsb-harness-external.md` Part 5 Gap 1
- agentpatterns.tech "Infinite Agent Loop" 패턴
- charmbracelet/crush GitHub issue #805

**스케치**: Stop 훅 또는 PostToolUse 가 최근 N 커맨드/에디트 를 비교, near-identical repeat (예: 같은 파일의 같은 라인을 3번 수정) 감지 시 hard stop + CEO 에스컬레이션. CLAUDE.md 룰은 유지하되 훅이 안전망.

**의존성**: 1.1 (audit log) 가 있으면 더 정확한 탐지 가능.
**상태**: `done` (2026-04-12, `templates/hooks/check-loop-breaker.sh` — PostToolUse Write|Edit 훅. 같은 파일 3회 수정 시 WARNING, 5회 시 ESCALATE. 11 assertions 통과)

### 3.2 AST-level CONTRACT enforcement [MED / Large]

**문제**: v7 의 CONTRACT.md FAQ 패턴은 산문 — "왜 X 가 제거됐나" 에 대한 답만 있고, X 가 **다시 추가되는 것을 기계적으로 막지 못함**. 에이전트가 CONTRACT.md 를 안 읽거나 읽고도 무시 가능.

**증거**: `docs/research/2026-04-11-tsb-harness-architect.md` §E.5.

**스케치**: `templates/contract-rules/` 에 ast-grep 패턴 정의. 예: "이 함수 시그니처에 `taCache` 파라미터 금지" 를 `ast-grep` 룰로 pre-commit 또는 CI 체크. CONTRACT.md 의 자연어 FAQ 는 **설명** 으로 유지, 강제는 ast-grep 룰이 담당.

**상태**: `todo`

### 3.3 Zombie resurrection git-diff hook [MED / Small]

**문제**: 과거 커밋에서 삭제된 코드/심볼이 다시 추가되는 것 감지. CONTRACT.md FAQ 는 사람이 읽는 설명이고, 이건 기계적 감지.

**스케치**: pre-commit 또는 pre-push 훅 — 커밋되는 라인 중에 "git log --diff-filter=D 로 과거 삭제된 심볼" 과 매칭되는 게 있으면 경고 + CONTRACT.md 참조 요청.

**상태**: `todo`

### 3.4 `.protected-files` entry validator with metadata [MED / Small]

**문제**: v7 의 `.protected-files` 는 plain list. "무엇이 flag 할 가치 있는 변경인가" 메타데이터 없음. 현재 architect trigger 는 binary (파일 이름 매칭 or not).

**스케치**: `.protected-files` 를 YAML 로 업그레이드:
```yaml
- file: api/_signal-engine.js
  reason: 시그널 엔진 코어, 크라운 주얼
  trigger_on: 
    - any_PCT_constant_change > 10
    - function_signature_change
    - any_change  # fallback
  reviewer: architect-opus
```

**상태**: `todo`

---

# Theme 4: Context & Memory

### 4.1 Instruction compliance decay counter + rule reinjection + anti-quit [HIGH / Medium]

**문제**: Khare decay curve — 메시지 5-6 이후 CLAUDE.md 룰 준수율 20-60%. 현재 idea-factory 는 세션 길이 카운터 없음. 중반 이후 핵심 룰을 재주입할 방법 없음.

이 decay 의 대표적 증상 두 가지:
1. **자의적 작업 중단 (anti-quit)**: 모델이 "오늘은 여기까지", "다음 세션에서 이어하자" 등 학습 데이터 패턴에 의해 스스로 작업을 중단. Claude 에는 피로·일일 한도 없으므로 이는 instruction decay 로 인한 잘못된 행동.
2. **반복 실패 루프 진입**: 컨텍스트 오염으로 이전의 틀린 접근법을 재참조하며 같은 버그를 수십 회 반복. (3.1 circuit breaker 와 연동)

**증거**: 
- `docs/research/2026-04-11-tsb-harness-external.md` Part 2 Failure Mode 4 (Jaroslawicz et al. 2025)
- https://dev.to/siddhantkcode/an-easy-way-to-stop-claude-code-from-forgetting-the-rules-h36
- 2026-04-12 사용자 리포트: 4개 터미널에서 동시에 자의적 중단 + 무한 루프 관찰

**스케치**:
1. **PreToolUse 훅 (exit 0)**: N 메시지마다 or 토큰 임계값마다 critical invariants 를 `<system-reminder>` 로 재주입. 재주입 대상 핵심 규칙:
   - "사용자가 명시적으로 중단 요청하기 전까지 자의적으로 작업을 중단하지 않는다"
   - "같은 접근법 3회 실패 시 근본 원인 분석 후 다른 전략으로 전환하거나 escalate"
   - 현재 세션의 핵심 목표 리마인더
2. **CLAUDE.md 템플릿 즉시 반영**: 훅 구현 전에도 prose rule 로 anti-quit 규칙 선행 배치 (v7.1 에서 바로 적용 가능)
3. **3.1 circuit breaker 와 연동**: decay counter 가 감지한 "반복 패턴" 정보를 3.1 에 전달

**의존성**: 없음 (독립 착수 가능). 3.1 과 시너지.
**상태**: `done` (2026-04-12, `templates/hooks/check-decay-counter.sh` — PreToolUse 훅. 40회 도구 호출마다 anti-quit + circuit breaker + context hygiene 규칙 재주입. CLAUDE.md 템플릿에도 prose rule 선행 배치. 12 assertions 통과)

### 4.2 Auto-compact loss validation for handoff docs [LOW / Large]

**문제**: Anthropic 발표처럼 compaction 은 "summary without clean slate" — 세부 제약 discipline 이 소실됨. Phase handoff docs 가 **실제로 복원 가능한지** idea-factory 는 테스트 안 함.

**스케치**: 가상의 "context reset 테스트" — fresh agent 에게 handoff.md 만 주고 원래 프로젝트 불변 조건을 재구성할 수 있는지 측정. 어렵고 결과 해석도 모호해서 우선순위 낮음.

**상태**: `todo`

### 4.3 Tried-and-failed session ledger [MED / Medium]

**문제**: `project-memory` 는 durable fact 용. 실패한 시도 ledger 는 없어서, 다음 세션이 "MOMENTUM_ENTRY_PCT 2.5" 를 네 번째로 재시도.

**증거**: `docs/research/2026-04-11-tsb-harness-architect.md` §E.9.

**스케치**: `.omc/experiments/failed.jsonl` append-only 로그. 각 실패 시도의 context (파일, 변경, 이유) 기록. 세션 시작 시 Claude 가 "내가 지금 시도하려는 게 이 로그에 있나?" 체크하도록 CLAUDE.md + project-memory 에 룰 추가.

**상태**: `todo`

---

# Theme 5: Domain Patterns

v7 까지 idea-factory 는 암묵적으로 **"웹앱 + Playwright UI"** 를 가정. 현장 적용 시 다른 도메인 (cron 봇, 데이터처리, ML, 트레이딩) 에는 fit 이 떨어짐.

### 5.1 Numerical tuning harness primitive [HIGH / Large]

**문제**: idea-factory 는 work = file diff 를 가정. 신호 봇/ML/추천/pricing 은 work = parameter delta. 이 패러다임이 first-class 가 아니어서 튜닝 세션이 ghost bug + evaluator leniency + fix-loop thrashing 의 3중 먹잇감.

**증거**: `docs/research/2026-04-11-tsb-harness-architect.md` §E.1.

**스케치**: 
- `templates/workflows/tuning-session.md` — 프로토콜 문서
- `scripts/tuning-gate.sh` — 파라미터 변경 PR 에 강제: (1) 변경 전 현재 값 + 근거 + 타깃 메트릭, (2) backtest 출력 trailer, (3) `decisions.md` 엔트리, (4) 한 파라미터 per 커밋
- `.omc/experiments/` 디렉터리 구조
- Numerical ADR 포맷 (decisions.md 변종)

**트레이딩 봇 외 적용 가능**: ML 하이퍼파라미터 튜닝, 추천 시스템 가중치, 가격 engine 파라미터.
**상태**: `todo`

### 5.2 Cron-bot project template [HIGH / Large]

**문제**: 현재 `start-company` 는 UI 있는 웹앱 스캐폴딩 전용. cron 봇/데이터 봇 은 다른 필요사항 (audit log, backtest harness, runtime metric 수집, rollback 스크립트, Discord/Slack as QA surface).

**증거**: `docs/research/2026-04-11-tsb-harness-architect.md` §E.6.

**스케치**: `templates/cron-bot/` 를 `templates/` (현재 암묵적 web-app) 의 sibling 으로 추가. 차이점:
- No Playwright (UI 없음)
- No `.project/essence.md` 에 "user-facing feel" 섹션
- Yes `.omc/audit/` 디렉터리
- Yes `scripts/backtest.js` / `scripts/replay.js` 
- Yes runtime metrics collector hook
- Yes `scripts/rollback.sh` 템플릿

**`start-company` 분기**: "이 프로젝트는 웹앱 인가요 봇 인가요?" 질문을 킥오프에 추가.
**의존성**: 5.1 (tuning harness) 와 자연스럽게 통합됨.
**상태**: `todo`

### 5.3 Runtime metrics quality ratchet variant [MED / Medium]

**문제**: v7 의 Quality Ratchet 은 commit-time 메트릭 (bundle size, test count). trading bot 같은 cron 서비스는 runtime 메트릭 (daily winrate, error rate, latency p99) 이 진짜 품질 신호.

**증거**: `docs/research/2026-04-11-tsb-harness-architect.md` §E.4.

**스케치**: `templates/scripts/runtime-ratchet.sh` — state store (Redis, Postgres, CloudWatch, Grafana) 에서 메트릭 pull, 이전 시간 윈도우와 비교, 회귀 감지 시 PR 머지 block.

**상태**: `todo`

### 5.4 Copied-code drift detection [MED / Small]

**문제**: trading-signal-bot 의 `_ta-core.js` 는 market-dashboard-v5 `taCalculator.js` 의 verbatim copy. 상류에서 drift 하면 버그. idea-factory 에 "이 파일은 copy 다" 개념 없음.

**증거**: `docs/research/2026-04-11-tsb-harness-architect.md` §E.7.

**스케치**: `templates/COPIED-FROM.md.tmpl` — 각 copy 파일에 대해 `{upstream_repo, upstream_path, upstream_commit, copied_at, reason_for_copy, sync_policy}` 기록. CI 체크가 주기적으로 upstream 과 diff 비교, 큰 drift 면 경고.

**상태**: `todo`

### 5.5 Temporal leakage lint (trading/time-series domain) [LOW / Medium]

**문제**: SysTradeBench (arxiv 2604.04812) 가 LLM 생성 트레이딩 코드의 `df.shift(-1)`, `iloc[-1]`, unseeded `random` 등 lookahead 버그를 정량 측정. idea-factory 는 도메인 특화 센서 없음.

**증거**: `docs/research/2026-04-11-tsb-harness-external.md` Part 4.

**스케치**: `templates/lints/temporal-leakage/` — ast-grep 패턴 모음 (JS + Python). 트레이딩/시계열 프로젝트 타입 선택 시 활성화.

**상태**: `todo` (5.2 cron-bot 템플릿과 함께 고려)

---

# Theme 6: Reviewer Gate Flexibility

### 6.1 Rule-driven reviewer gate sizing [MED / Medium]

**문제**: v7 의 4-reviewer gate (architect + critic + code-reviewer + qa-tester) 는 고정. 단일 파일 숫자 변경에는 overkill, doc-only PR 에는 불필요.

**증거**: `docs/research/2026-04-11-tsb-harness-architect.md` §A.4 (4→2 축소 근거).

**스케치**: `templates/gate-rules.yml`:
```yaml
- match: "*.md"
  reviewers: []
- match: ["**/*_signal*.js", "**/*_engine*.js"]
  reviewers: [architect, backtest-qa]
- match: "src/**/*.tsx"
  reviewers: [architect, code-reviewer, qa-tester]
- match: "src/auth/**"
  reviewers: [architect, critic, code-reviewer, security-reviewer]
```

`run-gate.sh` 가 변경 파일 패턴에 따라 동적으로 리뷰어 선택.
**상태**: `todo`

### 6.2 2-reviewer numeric-tuning gate preset [MED / Small]

**문제**: 6.1 의 구체적 preset — 파라미터 튜닝 전용.

**스케치**: `templates/gate-rules/presets/numeric-tuning.yml` — architect (opus, 구조/불변 체크) + backtest-qa (sonnet, 실사용 데이터 리플레이 + adversarial defect-first 프레이밍).

**의존성**: 5.1 (tuning harness), 6.1 (rule-driven gates).
**상태**: `todo`

---

# Theme 7: ECC-inspired Infrastructure (2026-04-12 추가)

`docs/research/2026-04-12-ecc-comparison.md` 에서 발견된 everything-claude-code 의 3개 infrastructure 패턴. idea-factory 의 워크플로 discipline 을 유지하면서 선별 흡수. ECC 의 181 skills 카탈로그 모델은 철학적으로 거부하되, 이 3개는 진짜 가치 있음.

### 7.1 Session 상태 persistence (PreCompact + SessionStart) [HIGH / Medium]

**문제**: idea-factory 의 MVP → Harden → Ship multi-phase workflow 는 long-running. context limit 치면 phase state 전부 날아감. 현재 핸드오프 docs 가 부분적 완화지만 compaction 경계에서 자동 save 없음.

**증거**: 
- `docs/research/2026-04-12-ecc-comparison.md` Gap §5 (HIGH — Session Persistence / PreCompact State Save)
- Anthropic Engineering Blog (2026-03): context anxiety + structured handoff

**스케치**: 
- `templates/hooks/pre-compact-save.sh` — PreCompact 훅. phase state, 현재 story status, essence.md snapshot 을 `.claude/state/session-YYYY-MM-DD-HH-MM.md` 에 기록. exit 0 보장
- `templates/hooks/session-start-restore.sh` — SessionStart 훅. 최근 session-*.md 파일 감지, 있으면 Claude 에게 읽기 권고하는 notice 출력
- idea-factory phase 모델에 맞게 adapt (ECC 의 generic state store 아니라)

**의존성**: 없음. 1.1 audit log 패턴과 유사한 훅 구조.
**상태**: `todo`

### 7.2 Cost tracking Stop hook [HIGH / Small]

**문제**: CEO 가 idea-factory 돌리다 $40 토큰 태운 걸 경고 없이 발견하면 안 됨. idea-factory 는 현재 cost 가시성 전혀 없음. ECC 의 `stop:cost-tracker` 는 가벼운 Stop 훅.

**증거**: `docs/research/2026-04-12-ecc-comparison.md` Gap §5 (HIGH — Cost Tracking Hook)

**구현** (2026-04-11, issue #9):
- `templates/hooks/stop-cost-summary.sh` — Stop 훅. stdin 으로 받는 hook payload 에서 `transcript_path` 추출, JSONL 파싱해서 input/output/cache_creation/cache_read 토큰 카테고리별 합산
- `.claude/audit/cost-YYYY-MM-DD.jsonl` 에 한 줄 append: `{ts, session, input_tokens, output_tokens, cache_creation_input_tokens, cache_read_input_tokens}`
- 첫 실행 시 `.claude/audit/.gitignore` 자동 생성
- 비용 환산은 의도적으로 안 함 (모델별/시점별 가격 변동 → raw 토큰만 영구 기록, 환산은 별도 도구)
- shell injection 방지: transcript_path 를 env var 로 python3 에 전달 (절대 shell interpolation 안 함)
- `templates/settings.json` 의 Stop hooks 배열에 등록 (timeout 5000ms, check-quality.sh 와 공존)
- `tests/hooks/stop-cost-summary.test.sh` — 14개 assertion (정상 합산, 빈 stdin, 누락 path, malformed JSONL, 빈 transcript, gitignore 자동 생성, JSONL 유효성, **shell injection 가드 카나리** 포함)

**의존성**: 없음. 1.1 audit log 와 같은 디렉터리 공유.
**상태**: `in-progress` (PR #10, 2026-04-11. 머지 시 `done` 로 업데이트)

### 7.3 Config protection hook [HIGH / Small]

**문제**: 에이전트가 TypeScript 에러 해결하려고 `tsconfig.json` 약화, ESLint 룰 비활성화, test coverage threshold 낮춤 — 장시간 빌드의 실제 failure mode. 에이전트는 "에러 없애기" 를 "코드 고치기" 로 해석 안 하고 "체크 낮추기" 로 해석.

**증거**: `docs/research/2026-04-12-ecc-comparison.md` Gap §5 (HIGH — Config Protection Hook). ECC 의 `pre:config-protection` 이 config 파일 쓰기 차단.

**스케치**: 
- `templates/hooks/check-config-protection.sh` — PostToolUse Write|Edit 훅
- 감지 대상 파일: `tsconfig.json`, `.eslintrc*`, `biome.json`, `jest.config.*`, `vitest.config.*`, `.github/workflows/ci*.yml`
- 해당 파일의 변경에서 "strictness 낮추는 패턴" 감지: `"strict": false`, `// @ts-ignore` 추가, `skipLibCheck`, `rules: { ... : "off" }`
- exit 0 보장 — 차단 아니라 audit log + 경고
- 또는 deny-list 에 해당 파일 읽기/쓰기 추가 (더 강함)

**의존성**: 없음.
**상태**: `todo`

---

# Wave 0: 안전 기반 (2026-04-12 시작)

v8 backlog 의 나머지 22개 항목을 안전하게 진행하기 위한 **pre-requisite**. 항목이 아니라 **인프라**.

### W0.1 Latent bug fix — SKILL.md:180 path ✅ DONE (PR #8)

**상태**: `done` (2026-04-12, PR #7)
**내용**: `skills/start-company/SKILL.md` 의 stale `~/.claude/agents/code-reviewer.md` literal path 참조를 subagent-name 기반 + vendored path 로 교체.

### W0.2 OMC 리뷰어 에이전트 vendoring ✅ DONE (PR #8)

**상태**: `done` (2026-04-12, PR #7)
**내용**: `templates/agents/` 에 다음 4개 vendor (OMC plugin cache 에서 verbatim copy):
- `architect.md`, `critic.md`, `code-reviewer.md`, `qa-tester.md`

효과: idea-factory 가 OMC 없는 사용자 머신에서도 완전 동작. OMC 는 여전히 optional recommended.

### W0.3 테스트 인프라 ✅ DONE (PR #8)

**상태**: `done` (2026-04-12, PR #7)
**내용**: 
- `tests/run-all.sh` — 테스트 러너
- `tests/hooks/check-audit.test.sh` — v8 item 1.1 의 fixture 기반 회귀 테스트 (10개 assertion)
- `tests/README.md` — 사용법 + "exit 0 불변식이 가장 중요" 설명

### W0.4 CI exit-0 불변식 검증 ✅ DONE (PR #8)

**상태**: `done` (2026-04-12, PR #7)
**내용**: 
- `tests/invariant-exit-zero.sh` — 모든 `templates/hooks/*.sh` 가 다양한 adversarial 입력 (정상, 빈, malformed JSON, binary, 1MB 거대, control chars) 에 exit 0 만 반환하는지 검증
- `.github/workflows/ci.yml` — PR/push 에 자동 실행
- **v7 회귀 재발 감지 하드 가드**

### W0.5 학습층 research 아카이브 ✅ DONE (PR #8)

**상태**: `done` (2026-04-12, PR #7)
**내용**: 2026-04-12 ECC 분석 + OMC 필요성 분석 리포트를 `docs/research/` 에 영구 보관 (verbatim).

---

## 📊 요약 통계

| Theme | HIGH | MED | LOW | DONE | 총 |
|---|---|---|---|---|---|
| 1. Runtime Safety | 1 | 2 | 1 | 0 | 4 |
| 2. Learning Layer | 1 | 0 | 1 | 3 | 5 |
| 3. Enforcement | 1 | 3 | 0 | 0 | 4 |
| 4. Context & Memory | 0 | 2 | 1 | 0 | 3 |
| 5. Domain Patterns | 2 | 2 | 1 | 0 | 5 |
| 6. Reviewer Gate | 0 | 2 | 0 | 0 | 2 |
| 7. ECC Infrastructure | 3 | 0 | 0 | 0 | 3 |
| **합계** | **8** | **11** | **4** | **3** | **26** |

Wave 0 (안전 기반, 별도 항목 아님): 5 sub-tasks, 전부 done (PR #7).

---

## 🎯 v8 권장 착수 순서 (제안, 강제 아님)

### Wave 1 — Foundation (learning layer 완성)
- 2.4 Session auto-capture — 향후 모든 세션이 이득을 봄 (compound)
- 1.1 Exit-0 audit log — runtime safety 의 핵심 gap, trading-signal-bot 이 첫 검증 사이트
- 3.1 Fix-loop 코드 강제 — 가장 흔한 실패 모드

### Wave 2 — Paradigm expansion
- 5.1 Numerical tuning harness primitive — 새 도메인 열림
- 5.2 Cron-bot template — 5.1 과 자연스럽게 쌍
- 1.3 Project-type deny-list extensions — 5.2 와 통합

### Wave 3 — Enforcement hardening
- 3.2 AST-level CONTRACT — 산문을 기계화
- 3.3 Zombie resurrection git-diff hook
- 3.4 .protected-files YAML 업그레이드

### Wave 4 — Resilience
- 4.1 Instruction compliance decay counter
- 4.3 Tried-and-failed ledger
- 6.1 Rule-driven gate sizing

### 나중에
- 1.2, 1.4, 2.5, 4.2, 5.3, 5.4, 5.5, 6.2

각 Wave 는 독립적으로 착수 가능. Wave 1 만 하고 멈춰도 상당한 가치.

---

## 📝 항목 추가 방법

새 gap 발견 시:

1. 적절한 Theme 에 항목 추가 (또는 새 Theme 생성)
2. 필수 필드: 문제 / 증거 (docs/research 또는 docs/field-reports 링크) / 스케치 / 우선순위 / 상태
3. 의존성 있으면 명시
4. 요약 통계 테이블 업데이트
5. 커밋 메시지: `docs: add v8 backlog item X.Y` 또는 `docs: update v8 backlog item X.Y status`

## 📝 상태 업데이트 방법

- `todo` → `in-design`: 설계 문서 작성 시작할 때. 설계 문서는 `docs/plans/v8-designs/{item-id}.md`
- `in-design` → `in-progress`: 구현 PR 오픈 시
- `in-progress` → `done`: PR 머지 + 릴리스 포함
- `todo` → `deferred`: 미루기로 결정했을 때, 사유 필수
