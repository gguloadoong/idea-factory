# idea-factory Examples

실제 `/start-company` 실행 결과물 갤러리. 한 줄 아이디어 → 작동하는 MVP 사례 모음.

이 디렉터리는 Lovable / Bolt 같은 경쟁 제품이 보유한 "샘플 갤러리" 포지션을 채운다.
외부 방문자가 "이거 진짜 동작해?"를 판단할 수 있는 증거물 역할.

---

## 수록 기준

각 예시는 다음을 포함한다:

| 필드 | 설명 |
|---|---|
| **아이디어** | CEO가 입력한 한 줄 (`/start-company "..."`) |
| **생성 결과** | 생성된 레포 링크 + 스크린샷 1장 이상 |
| **Phase 도달** | MVP / Harden / Ship 중 어디까지 |
| **소요 시간** | 빌드 + 검증 합산 |
| **CEO 개입 횟수** | A/B/C 선택 + 승인 횟수 |
| **모델 사용량** | Sonnet 호출 수 + Opus 호출 수 (토큰 총량) |
| **교훈** | 이 예시에서 얻은 패턴/안티패턴 |

---

## 샘플 카테고리

### SaaS / Web App

- [ ] **CashFreel** — 프리랜서 수입·지출 자동 관리 (예정)
- [ ] 바쁜 투자자용 포트폴리오 트래커 (예정)
- [ ] 중고생 AI 학습 계획 (예정)

### Cron / Trading Bot

- [ ] 암호화폐 시그널 알림 봇 (예정)
- [ ] 주가 이상 감지 봇 (예정)

### Internal Tool

- [ ] 병원 예약·리포트 자동화 (예정)
- [ ] 소규모 팀 회계 어시스턴트 (예정)

---

## 기여 방법

새로운 샘플을 추가하려면:

1. `examples/{slug}/` 디렉터리 생성 (kebab-case, 영문)
2. `{slug}/README.md`에 위 테이블 템플릿대로 기록
3. `{slug}/screenshot.png` 1장 이상 (옵션)
4. 원본 레포 링크 (공개 가능 시)
5. PR 제출 — 루트 [CONTRIBUTING.md](../CONTRIBUTING.md) 참고

### README 템플릿

```markdown
# {서비스명}

**아이디어**: `/start-company "한 줄 아이디어"`

| 항목 | 값 |
|---|---|
| 생성 레포 | https://github.com/... |
| Phase 도달 | MVP / Harden / Ship |
| 소요 시간 | ~N시간 |
| CEO 개입 | N회 |
| 모델 사용량 | Sonnet Nk + Opus Nk tokens |

## 스크린샷

![screenshot](./screenshot.png)

## 교훈

- 잘 된 점: ...
- 고칠 점: ...
- 다음에 다르게 하면: ...
```

---

## 참고

- [/start-company 실행 가이드 (한국어)](../docs/ko/README.md#사용법)
- [HARNESS-GUIDE.md](../skills/start-company/HARNESS-GUIDE.md) — 설계 철학
- [ARCHITECTURE.md](../ARCHITECTURE.md) — 시스템 구조
