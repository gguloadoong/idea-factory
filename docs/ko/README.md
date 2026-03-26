# idea-factory 한국어 가이드

> 아이디어 한 줄이면 가상 스타트업이 MVP를 만들어줍니다.

## 이게 뭔가요?

Claude Code를 가상 스타트업 팀으로 바꿔주는 도구입니다. 당신은 CEO — 아이디어만 말하면 AI 팀(PM, 개발자, 디자이너)이 자율적으로 만듭니다.

## 설치

```bash
git clone https://github.com/gguloadoong/idea-factory.git
cd idea-factory
bash install.sh
```

### 필수 환경
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code)
- Node.js 18+
- Git
- (선택) [oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode) — ralph 자율주행 루프용

## 사용법

Claude Code를 열고:

```
/start-company 직장인 투자자를 위한 통합 포트폴리오 앱
```

끝입니다. 시스템이 알아서:
1. 아이디어를 분석하고 최소 팀을 구성합니다
2. 프로젝트 구조를 만듭니다
3. 쉬운 말로 3-5개 질문을 합니다
4. 자율주행으로 MVP를 만듭니다

## 언제 당신에게 물어보나요?

이것만:
- **킥오프 결정** — 디자인 느낌, 범위, 수익 모델 (전문 용어 없이)
- **MVP 검증** — "이 방향이 맞나요?"
- **유료 자원** — API 키, 호스팅, 계정
- **큰 방향 전환** — 팀이 피벗이 필요하다고 판단할 때

나머지는 전부 팀이 알아서 합니다.

## 핵심 철학: MVP 먼저

대부분의 AI 코딩 도구는 바로 실제 API 연결 + 배포로 달려갑니다. idea-factory는 반대입니다:

1. **Phase 1 — 프로토타입**: 가짜 데이터로 핵심만 만들기. "이게 내가 원하던 거야?"
2. **Phase 2 — 고도화**: 실제 API, 에러 처리, 테스트. Phase 1 검증 후에만.
3. **Phase 3 — 배포**: Phase 2 보안 감사 통과 후에만.

## 본질 검증

모든 기능은 서비스의 핵심 "왜"에 대해 검증됩니다:
- 이 기능이 서비스가 존재하는 이유에 기여하는가?
- 와우 팩터를 강화하는가, 약화하는가?
- 원래 비전에서 벗어나고 있지 않은가?

너무 벗어나면 → 시스템이 알려주고 피벗을 제안합니다.

## 다른 도구와 비교

| 도구 | 접근법 | 당신이 되어야 하는 것 |
|------|--------|---------------------|
| 바이브 코딩 | "그냥 만들어" | 개발자 |
| gstack | 개발팀 시뮬레이션 | 개발자 |
| **idea-factory** | **스타트업 시뮬레이션** | **CEO만 하면 됨** |

## 예시 아이디어

```
/start-company 반려동물 건강 관리 앱
/start-company 시니어 대상 건강 식단 배달 구독 서비스
/start-company 중소병원용 예약·문진·리포트 자동화 운영툴
/start-company 프리랜서 수입/지출 자동 관리 앱
```

## 문제가 있나요?

GitHub Issues에 남겨주세요. 한국어 OK.
