# Claude Code Routines — 아이디어 자동화 가이드

> **상태**: 2026-04-14 리서치 프리뷰 출시. 스키마·한도·API는 변경될 수 있음.

---

## Routines란 무엇인가

Claude Code Routines는 Claude Code 세션을 클라우드에서 자동으로 실행하는 기능이다.
로컬 터미널을 열지 않아도, 맥북이 꺼져 있어도 작업이 돌아간다.

**핵심 개념**: 루틴 = 프롬프트 + 레포지토리 + 환경(시크릿·툴) + 트리거.
한 번 설정하면 조건이 맞을 때마다 Claude가 알아서 실행한다.

**2026-04-14 의미**: 지금까지 `/start-company`를 실행하려면 터미널을 켜야 했다.
Routines 출시 이후로는 "아이디어를 GitHub Issue에 올리면 → Claude가 알아서 MVP 스캐폴딩까지"
하는 흐름이 가능해졌다. 대표가 코드 한 줄 없이 아이디어를 접수하고 자동으로 PR을 받는 세계다.

---

## 트리거 유형 3가지

| 트리거 | 설명 | idea-factory 활용 예 |
|---|---|---|
| **Schedule** | 시간 기반 반복 실행 (매시·매일·매주 등) | 매주 월요일 아침 백로그 정리 |
| **GitHub Event** | PR 생성·릴리즈 등 GitHub 이벤트 반응 | Issue 등록 시 `/start-company` 자동 실행 |
| **API** | HTTP POST로 온디맨드 실행 | 외부 알림 시스템이 루틴을 직접 호출 |

단일 루틴에 여러 트리거를 동시에 붙일 수 있다.
예: GitHub Issue 트리거 + API 트리거를 같은 루틴에.

---

## 요금제별 일일 한도 (2026-04-14 기준)

| 요금제 | 일 실행 한도 |
|---|---|
| **Pro** | 5회/일 |
| **Max** | 15회/일 |
| **Team / Enterprise** | 25회/일 |

한도 초과 시 `Settings > Billing`에서 추가 사용(extra usage)을 활성화하면
초과분은 종량제로 계속 실행된다. 비활성화 상태이면 한도 초과 루틴은 거부된다.

**아이디어 팩토리 운영 기준**: 아이디어가 하루 5개 이하이면 Pro로 충분하다.
스타트업 초기 아이디어 폭발 기간이라면 Max 이상을 권장한다.

현재 소비량 확인: `https://claude.ai/settings/usage`

---

## idea-to-mvp 루틴 — 사용 예시

### 흐름 요약

```
대표가 GitHub Issue 등록
  (제목: "고양이 SNS", 라벨: idea)
        │
        ▼
Routine 자동 트리거
        │
        ▼
Claude가 /start-company "고양이 SNS" 실행
        │
        ▼
MVP 스캐폴딩 완료 → PR 생성
        │
        ▼
Discord 채널에 알림 + Issue에 PR 링크 코멘트
```

### 설정 단계

1. `claude.ai/code/routines`에서 **New routine** 클릭
2. 이 폴더의 `idea-to-mvp.yaml` 값을 참고해 폼 입력
3. 환경 변수 설정 (아래 섹션 참고)
4. GitHub 트리거 선택 → 레포 연결 → 라벨 필터 `idea` 설정
5. **Create** 클릭 → 루틴 저장

CLI로 생성하려면 Claude Code 세션에서:
```
/schedule idea-to-mvp: GitHub Issue(라벨 idea) 등록 시 /start-company 실행 후 Discord 알림
```

---

## 디스코드 Webhook 준비 방법

**절대 규칙: Webhook URL을 코드나 YAML에 하드코딩하지 않는다.**

### Discord에서 Webhook URL 발급

1. Discord 서버 → 채널 설정 → **연동** → **웹후크**
2. **새 웹후크** → 이름 지정 → **웹후크 URL 복사**
3. URL 형식: `https://discord.com/api/webhooks/<ID>/<TOKEN>`

### Claude Cloud 환경에 등록

1. `claude.ai/code/routines` → **Settings > Environments**
2. 루틴에 연결된 환경 선택 (또는 새 환경 생성)
3. Environment Variables에 추가:
   - `DISCORD_WEBHOOK_URL` = 복사한 Webhook URL
   - `GITHUB_TOKEN` = repo 권한이 있는 Personal Access Token 또는 GitHub App 토큰
4. **저장** — 이제 루틴 실행 시 `${DISCORD_WEBHOOK_URL}`로 값을 읽는다

루틴 프롬프트 안에서 Claude는 이 환경변수를 자동으로 사용할 수 있다.

---

## 한계 및 주의사항

### 실험적 기능 (Research Preview)

- 스키마·API·한도는 예고 없이 변경될 수 있다.
- GitHub 트리거는 현재 `pull_request`와 `release` 이벤트만 지원.
  Issues 이벤트 구독은 아직 미지원 → API 트리거로 우회 (YAML 주석 참고).
- GitHub webhook 이벤트에는 시간당 루틴당 별도 상한이 있다.
  아이디어가 짧은 시간에 대량 접수되면 일부가 드롭될 수 있다.

### 컨텍스트 제약

루틴은 매 실행마다 새 세션으로 시작된다. 이전 실행의 컨텍스트를 기억하지 않는다.
장기 실행 루틴(예: `/start-company` 전체 7단계)은 1M 컨텍스트 윈도우 내에서
동작하지만, 세션 간 상태는 파일(handoff 문서, `.project/`)로 넘겨야 한다.

### 권한 범위 최소화

루틴은 승인 프롬프트 없이 완전 자율 실행된다.
레포지토리 접근 범위, 환경변수, 커넥터를 루틴이 실제로 필요한 것만으로 제한할 것.
기본적으로 Claude는 `claude/`로 시작하는 브랜치에만 push한다.
무제한 브랜치 push는 명시적으로 활성화해야 한다.

---

## 보안 규칙

이 프로젝트의 시크릿 정책을 루틴에도 동일하게 적용한다:

- **DISCORD_WEBHOOK_URL**, **GITHUB_TOKEN** 등 모든 시크릿은 `${VAR_NAME}` 플레이스홀더만 사용
- YAML 파일, 프롬프트 텍스트, 커밋 메시지에 실제 토큰값 절대 포함 금지
- Claude의 인증은 OAuth 2.1 기반 — 단기 토큰이 세션마다 발급됨
- API 트리거 토큰은 생성 직후 1회만 표시됨 → 즉시 안전한 저장소에 보관
- 토큰 노출이 의심되면 루틴 편집 > API 트리거 모달 > **Regenerate** 즉시 실행

---

## 참고 링크

- 루틴 관리 UI: `https://claude.ai/code/routines`
- 공식 문서: `https://code.claude.com/docs/en/routines`
- 출시 포스트: `https://claude.com/blog/introducing-routines-in-claude-code`
- 통합 가이드 (영문+한국어): `../../docs/routines-integration.md`
