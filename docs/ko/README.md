<div align="center">

# idea-factory 🏭

### 아이디어 한 줄이면, 작동하는 MVP가 나옵니다.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Compatible-blueviolet)](https://docs.anthropic.com/en/docs/claude-code)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](http://makeapullrequest.com)

**idea-factory**는 Claude Code를 가상 스타트업 팀으로 바꿔줍니다.<br>
당신은 CEO — 원하는 것을 한 줄로 설명하면, AI 에이전트 팀이 만들어줍니다.

[빠른 시작](#설치) · [작동 방식](#작동-방식-how-it-works) · [English Guide](../../README.md)

</div>

---

## 🚀 v7.1 핵심 변경

**v7.1 (2026-04-11)** 은 v7의 핫픽스입니다. 자율주행 워크플로우(autonomous workflow)를 멈추게 하던 PreToolUse 훅(hook)을 제거했습니다 (참고: [#2](https://github.com/gguloadoong/idea-factory/issues/2)).
`templates/settings.json`은 이제 `defaultMode: "bypassPermissions"`와 빈 `PreToolUse`를 기본값으로 탑재합니다. 위험한 명령(`rm -rf /`, `sudo *`, `.env*`, 자격증명, 시크릿)은 여전히 `deny` 목록으로 차단됩니다.

**v7 (2026-04-04)** 는 핵심 엔진 전면 개선판입니다. market-dashboard-v5에서 검증된 11가지 패턴을 도입했습니다: Quality Ratchet(품질 하한선), Protected Files(보호 파일), 5단계 PR 파이프라인, 6관문 배포 합의, CONTRACT FAQ, 에이전트 깊이 가이드 등. 전체 변경 이력은 [HARNESS-GUIDE.md](../../skills/start-company/HARNESS-GUIDE.md#changelog)를 참고하세요.

**v6.1** 은 기반을 다진 버전입니다: 4인 리뷰어 관문, 격리된 워크트리(worktree), 2단계 평가, Playwright MCP, 단계 핸드오프 문서, Codex Gate. [Anthropic의 하네스 엔지니어링 연구](https://www.anthropic.com/engineering/harness-design-long-running-apps)(2026년 3월)를 바탕으로 설계됐습니다.

| 기능 | 설명 |
|------|------|
| **4인 리뷰어 관문** | architect + critic + code-reviewer + qa-tester가 병렬로 검토 (기존 3인 → 4인) |
| **독립 컨텍스트 격리** | 모든 리뷰어는 격리된 워크트리에서 실행 — 자기 칭찬 편향 없음 |
| **2단계 평가** | 1단계: 결함 찾기(필수). 2단계: 점수 채점(선택, 새 컨텍스트). "평가자 관대함" 제거 |
| **Playwright MCP** | qa-tester가 실제 브라우저로 앱을 열고, 버튼을 클릭하고, 폼을 채움 — 코드 리뷰만이 아님 |
| **단계 핸드오프 문서** | MVP, Harden, Ship 단계마다 핸드오프 문서를 생성해 컨텍스트를 보존 |
| **Codex Gate** | OpenAI Codex CLI로 diff에 대한 교차 모델 리뷰 (선택 사항) |
| **deny-list 안전망** | `permissions.deny`가 위험 명령과 민감한 파일 읽기를 차단. PreToolUse 훅 없음 — 자율 워크플로우가 막힘 없이 동작 |
| **CLAUDE.md 80줄 제한** | 생성되는 프로젝트 CLAUDE.md를 80줄 이내로 유지 (HumanLayer 연구: 150줄 초과 시 준수율 급락) |
| **수정 루프 차단기** | 같은 실패 3번 = 멈추고 CEO에게 에스컬레이션 (무한 토큰 소모 루프 방지) |
| **HARNESS-GUIDE.md** | 모든 아키텍처 결정을 근거와 함께 설명하는 설계 문서 |

---

## Demo

명령어 하나. 한 시간 이내에 완성된 MVP.

```terminal
$ claude
> /start-company 프리랜서 수입 지출 자동 관리 앱

[ANALYZE] analyst + architect가 병렬로 분석 중...
  → 서비스명: CashFreel (캐시프릴)
  → 유형: SaaS — 프리랜서 세금 예측
  → 팀: PM + Developer + Designer

[SCAFFOLD] 템플릿으로 프로젝트 생성 중...
  → CLAUDE.md, agents, hooks, settings ✓
  → git init ✓

[KICKOFF] CEO님, 빠른 질문 4가지:
  1. 디자인 느낌? → 토스 스타일 (미니멀, 큰 숫자)
  2. MVP 범위? → 세금 예측 + 수입/지출 추적
  3. 수익 모델? → 무료 먼저, 나중에 결정
  4. 수입 범위? → 국내 + 해외

[BUILD] ralph 루프로 MVP 스토리 실행 중...
  ✅ MVP-001: Next.js + Tailwind + shadcn/ui
  ✅ MVP-002: 수입 등록 (KRW + USD + EUR)
  ✅ MVP-003: 지출 추적 + 자동 분류
  ✅ MVP-004: 실시간 세금 대시보드 + 차트
  ✅ MVP-005: 현금흐름 리포트 + CSV 내보내기

[VALIDATE] 4명의 독립 리뷰어 (격리된 워크트리):
  ✅ architect (opus): Phase 2로 가는 구조적 문제 없음
  ✅ critic (opus): 본질 이탈 감지 없음
  ✅ code-reviewer (opus): 치명적 0개, 보통 2개 (비차단)
  ✅ qa-tester (playwright): 실제 브라우저에서 7개 플로우 모두 통과

→ MVP 완료. 준비되면 Phase 2를 시작하세요.
```

**결과:** CashFreel의 작동하는 프로토타입이 완성됩니다. 다음 단계: 실제 세금 API 연결, 인증 추가, 보안 강화. CEO는 코드 한 줄도 작성하지 않았습니다.

---

## 🏗️ 왜 idea-factory인가?

바이브 코딩(vibe coding)은 빠릅니다. 하지만 혼돈스럽습니다. 코드는 나오지만, 제품은 아닙니다.

진짜 스타트업에는 개발자만 있지 않습니다. **프로세스**가 있습니다: "안 돼"라고 말하는 PM, 그리기 전에 리서치하는 디자이너, 일부러 부수는 QA, "근데 왜?"를 묻는 비평가.

**idea-factory**는 두 가지를 모두 줍니다: AI의 속도 + 실제 팀의 규율.

<table>
<tr>
<td align="center"><b>도구</b></td>
<td align="center"><b>접근법</b></td>
<td align="center"><b>당신이 되어야 하는 것</b></td>
</tr>
<tr>
<td>바이브 코딩</td>
<td>"그냥 만들어"</td>
<td>개발자</td>
</tr>
<tr>
<td><a href="https://github.com/garrytan/gstack">gstack</a></td>
<td>엔지니어링 팀</td>
<td>개발자</td>
</tr>
<tr>
<td><b>idea-factory</b></td>
<td><b>풀 스타트업 팀</b></td>
<td><b>CEO만 하면 됨</b></td>
</tr>
</table>

---

## 작동 방식 (How It Works)

```
당신: /start-company 바쁜 투자자를 위한 포트폴리오 트래커
```

```
  ANALYZE ──────── 두 에이전트가 병렬로 아이디어를 분석
     │              (시장 적합성, 기술 스택, 팀 구성)
     ▼
  SCAFFOLD ─────── 처음부터 생성이 아닌, 템플릿에서 프로젝트 생성
     │
     ▼
  KICKOFF ──────── 전문 용어 없는 3-5개의 간단한 질문
     │
     ▼
  BUILD MVP ────── 가짜 데이터 먼저. 핵심 플로우만.
     │              모든 기능 확인: "이게 핵심 Why에 기여하는가?"
     ▼
  VALIDATE ─────── 격리된 워크트리에서 4명의 리뷰어 (결함 먼저):
     │              Architect + Critic + Code-Reviewer + QA (Playwright)
     │              ↳ 치명적 결함? 수정 후 재시도. 모두 통과? CEO 확인.
     ▼
  HARDEN ──────── 실제 API, 테스트, 보안 — MVP 검증 후에만
     │
     ▼
  SHIP ────────── 배포 + 회고
```

---

## MVP-First 철학

> 대부분의 AI 도구는 API 연결과 배포로 서둘러 달려갑니다. 우리는 반대로 합니다.

| 단계 | 무슨 일이 일어나는가 | 실제 API? | 배포? |
|------|---------------------|:---------:|:-----:|
| **1 — 프로토타입** | 가짜 데이터, 핵심 플로우, "와우" 검증 | 아니오 | 아니오 |
| **2 — 고도화** | 실제 API, 에러 처리, 테스트, 보안 | 예 | 아니오 |
| **3 — 배포** | 보안 감사 통과 후 배포 | 예 | 예 |

**왜?** 누군가 원하는지 알기도 전에 결제 API를 연결하는 건 모두의 시간 낭비입니다.

---

## Essence 검증

모든 기능은 서비스의 핵심 **"왜(Why)"** 에 대해 검증됩니다:

```
essence.md
├── One-Line Definition: 이것이 무엇인지
├── Why This Exists:     어떤 문제를 해결하는지
├── Wow Factor:          사용자가 "와!"를 외치게 하는 것
├── Differentiator:      경쟁자가 하지 않는 것
└── Key Metric:          중요한 숫자 하나
```

- 매 스토리 이후: 이것이 핵심 Why에 기여하는가?
- 모든 관문에서: 코드베이스가 비전에서 이탈하고 있는가?
- 너무 벗어나면 → 시스템이 신호를 보내고 **피벗**을 제안합니다

---

## 설치

```bash
# 원라이너 (one-liner)
curl -fsSL https://raw.githubusercontent.com/gguloadoong/idea-factory/main/install.sh | bash

# 또는 직접 클론
git clone https://github.com/gguloadoong/idea-factory.git
cd idea-factory && bash install.sh
```

### 전제조건

| 필수 | 선택 |
|------|------|
| [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) | [oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode) (`ralph` 자율주행 루프용) |
| Node.js 18+ | Gemini CLI (외부 관점 리뷰용) |
| Git | |

---

## 사용법 (Usage)

```
/start-company 바쁜 투자자를 위한 포트폴리오 트래킹 앱
```

이것으로 끝입니다. 시스템이 자동으로:
1. 아이디어를 분석하고 최소 팀을 구성합니다
2. 올바른 구조로 프로젝트를 셋업합니다
3. 간단한 질문 3-5개를 합니다
4. 자율적으로 빌드를 시작합니다

### 언제 당신에게 물어보나요?

| 물어보는 것 | 물어보지 않는 것 |
|-------------|----------------|
| 디자인 느낌 (A/B/C 선택지) | 기술 스택 결정 |
| MVP 범위 | 아키텍처 선택 |
| 수익 모델 | 코드 리뷰 결과 |
| "이 방향이 맞나요?" | 버그 수정 |
| 실제로 필요할 때 API 키 | 팀이 결정할 수 있는 모든 것 |

---

## 무엇이 들어있나 (What's Inside)

```
idea-factory/
├── skills/start-company/         # 트리거 (/start-company)
│   ├── SKILL.md                   # 실행 플로우 (현재: v7.1)
│   └── HARNESS-GUIDE.md           # 설계 결정 + 근거 (22 KB)
│
├── templates/                    # 새 프로젝트에 복사되는 스캐폴드
│   │                              # ── 핵심 (모든 설치에 포함) ──
│   ├── CLAUDE.md.tmpl             # 프로젝트 헌법 (80줄 제한)
│   ├── settings.json              # 권한 + deny-list (안전 기준선)
│   ├── agents/                    # 7개 역할: pm · developer · designer · architect · critic · code-reviewer · qa-tester
│   ├── hooks/                     # 18개 이상 훅: safety / quality / governance / loop-breaker
│   ├── documents/                 # PRD · essence · CONTRACT · handoff · quality-baseline
│   ├── scripts/                   # codex-review-gate · copy-drift · contract · temporal-lint
│   ├── .github/workflows/         # CI + PR 라벨링
│   │                              # ── 고급 (선택적 패턴) ──
│   ├── contract-rules/            # CONTRACT FAQ 규칙 (이탈 가드레일)
│   ├── gate-presets/              # 6관문 배포 합의 설정
│   ├── gate-rules.yml             # 단계별 관문 규칙
│   ├── ratchet.yml.tmpl           # Quality Ratchet (품질 하한선)
│   ├── protected-files.yml        # 보호 파일 훅 허용 목록
│   ├── .protected-files.tmpl      # (다운스트림용 템플릿)
│   ├── handoff-checklist.md.tmpl  # 단계 핸드오프 체크리스트
│   ├── research-report.md.tmpl    # researcher 에이전트 출력 템플릿
│   ├── experiments/               # 수치 튜닝 하네스 (v8)
│   ├── cron-bot/                  # 스케줄 봇 스캐폴드 (v8)
│   ├── settings-extensions/       # 프로젝트 유형별 설정 오버레이
│   ├── lints/temporal-leakage/    # 날짜/시간 하드코딩 린트
│   ├── workflows/                 # ralph/ulw 워크플로우
│   ├── .githooks/                 # 다운스트림용 pre-commit 훅
│   ├── .coderabbit.yaml           # CodeRabbit 리뷰 설정
│   ├── COPIED-FROM.md.tmpl        # 템플릿 출처 스탬프
│   └── vercel.json                # Vercel 프리뷰 배포 안전 기본값
│
├── scripts/                      # 메타 유틸리티 (다운스트림에 복사되지 않음)
│   ├── sync-downstream.sh         # N개 다운스트림 레포에 템플릿 업데이트 전파
│   ├── sync-lib.py                # 동기화 라이브러리
│   ├── audit-backlog.py           # v8 백로그 추적
│   ├── check-contract.sh          # CONTRACT FAQ 이탈 검사
│   ├── check-copy-drift.sh        # 템플릿-복사본 이탈 검사
│   ├── lint-temporal-leakage.sh   # 날짜 린트
│   ├── merge-settings.sh          # settings.json 병합 헬퍼
│   ├── record-failure.sh          # 학습 레이어용 실패 기록
│   ├── run-gate.sh                # 관문 오케스트레이터
│   ├── tuning-gate.sh             # 수치 튜닝 관문
│   └── validate-handoff.sh        # 핸드오프 검증
│
├── sync-manifest.json            # managed / computed / customized 분류
├── downstream-registry.json      # 이 팩토리가 추적하는 다운스트림 레포
├── install.sh                    # 원커맨드 설치 스크립트
├── tests/                        # 하네스 불변 테스트
│
├── docs/                         # 프로젝트 문서
│   ├── ko/                        # 한국어 가이드
│   └── research/                  # 내부 리서치 메모
│
├── CLAUDE.md                     # 이 레포에서 작업할 때의 규칙 (Claude Code)
├── AGENTS.md                     # OMC 진입점
├── ARCHITECTURE.md               # 시스템 아키텍처 개요
├── CHANGELOG.md                  # 버전 이력
├── CONTRIBUTING.md               # 기여 가이드
├── SECURITY.md                   # 보안 정책
├── CODE_OF_CONDUCT.md            # 커뮤니티 기준
└── LICENSE                       # MIT
```

모든 설계 결정의 근거는 [HARNESS-GUIDE.md](../../skills/start-company/HARNESS-GUIDE.md)를 참고하세요.

---

## 설계 결정

| 결정 | 이유 |
|------|------|
| **생성이 아닌 템플릿** | 처음부터 30개 파일을 만들면 보일러플레이트에 컨텍스트 윈도우를 낭비함 |
| **ralph를 백본으로** | 스킬 간 후조건 체이닝(post-condition chaining)은 신뢰할 수 없음; 상태 머신 루프는 다름 |
| **4명의 격리된 리뷰어** | 같은 세션에서의 역할극은 진짜 분석이 아님; 워크트리로 격리된 에이전트가 진짜 |
| **결함 먼저, 점수 나중** | 점수만 매기면 "평가자 관대함"이 발생 (AI가 9/10을 줌). 결함 찾기가 먼저여야 솔직해짐 |
| **QA에 Playwright MCP** | 코드 리뷰만으로는 UI 버그를 놓침; 실제 브라우저 인터랙션이 사람이 잡는 것을 잡음 |
| **essence.md를 북극성으로** | 없으면 2번의 스프린트 안에 기능이 원래 비전에서 이탈함 |
| **CLAUDE.md 80줄 이내** | AI 준수율이 150줄 초과 시 급락; 시스템 프롬프트가 ~50줄 사용, 프로젝트용으로 ~100줄 남음 |
| **수정 루프 차단기** | 한도가 없으면 에이전트가 같은 오류에서 무한 재시도 루프로 토큰을 태움 |

---

## Examples

```bash
/start-company 반려동물 건강 관리 앱
/start-company 시니어 대상 구독형 건강 식단 배달 서비스
/start-company 중소병원 예약·문진·리포트 자동화 운영툴
/start-company 프리랜서 수입/지출 자동 관리 앱
/start-company AI 기반 대학생 학습 플래너
```

---

## 영감받은 프로젝트

- [gstack](https://github.com/garrytan/gstack) — 스프린트 파이프라인, 메타 스킬
- [Citadel](https://github.com/SethGammon/Citadel) — 단일 진입점 라우팅
- [oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode) — 에이전트 오케스트레이션
- [everything-claude-code](https://github.com/affaan-m/everything-claude-code) — 크로스플랫폼 스킬

---

## 기여하기

PR 환영합니다! 새 에이전트 템플릿, 더 나은 훅, 번역 — 무엇이든 좋습니다.

- 기여 절차는 [CONTRIBUTING.md](../../CONTRIBUTING.md)를 참고하세요
- 버그 리포트와 기능 제안은 GitHub Issues에 남겨주세요 (한국어 OK)
- 새 에이전트 역할이나 훅 패턴 추가도 환영합니다

---

## 라이선스

[MIT](../../LICENSE) — 자유롭게 사용하고, 수정하고, 배포하세요.

---

<div align="center">
<sub>Claude Code로 만들었습니다. 코드보다 제품을 생각하고 싶은 창업자를 위해.</sub>
</div>
