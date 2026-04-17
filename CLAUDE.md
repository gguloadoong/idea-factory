# idea-factory — 메타 레포 거버넌스

이 레포는 **Claude Code + OMC 기반 가상 스타트업 팩토리**의 템플릿·스킬·스크립트 원본이다.
여기서 작업하면 `/start-company`로 생성되는 모든 다운스트림 레포에 영향이 전파된다.
다운스트림 프로젝트에서 쓰이는 `CLAUDE.md`는 이 파일이 아니라 `templates/CLAUDE.md.tmpl`에서 나온다.

---

## 작업 영역 구분

| 디렉터리 | 역할 | 변경 빈도 |
|---|---|---|
| `templates/` | 다운스트림에 복사되는 파일 원본 (hooks, agents, scripts 등) | 높음 — 변경 시 전파 주의 |
| `skills/` | `/start-company` 실행 로직 (`SKILL.md`, `HARNESS-GUIDE.md`) | 중간 |
| `scripts/` | 메타 레포 관리 스크립트 (`sync-downstream.sh` 등) | 낮음 |
| `docs/` | 한국어 가이드 등 문서 | 낮음 |

---

## 보호 영역 — 반드시 PR 경유

다음 파일은 직접 main 커밋 금지. Issue → Branch → PR → 리뷰 후 머지:

- `sync-manifest.json` — managed 항목 변경 시 `sync-downstream.sh` 재실행 필요
- `downstream-registry.json` — 10개 다운스트림 레포 추적 목록
- `templates/CLAUDE.md.tmpl` — 생성되는 모든 프로젝트의 헌법 (80줄 제한 유지)
- `templates/settings.json` — `permissions.deny` 및 `defaultMode` 포함 (자율 루프 호환성 임계값)
- `templates/hooks/` — PreToolUse 훅은 반드시 exit-0 로깅 전용 (blocking 금지)

---

## 전파 영향 경고

`templates/` 하위 파일을 변경하면 현재 `downstream-registry.json`에 등록된
**10개 레포** (signalplay, chimp-pick, market-dashboard-v5, trading-signal-bot,
bull-vs-bear, costock, reel-forge, aptner, catchflow, market-dashboard-v2)
에 영향을 줄 수 있다.

변경 후 `sync-manifest.json`의 `managed` 항목에 해당하는 경우 반드시 갱신하고
`sync-downstream.sh`로 전파 여부를 확인한다.

---

## 커밋 규약

| 타입 | 경로 | 방식 |
|---|---|---|
| `feat:` `fix:` | 신규 기능·버그 수정 | Issue → `feature/#N-설명` 브랜치 → PR |
| `refactor:` `docs:` `chore:` | 리팩터·문서·유지보수 | main 직접 커밋 허용 |

한국어 원자적 커밋. 예: `feat: VALIDATE 게이트 4번째 리뷰어 추가 (#12)`

---

## 모델 라우팅

- **Sonnet 4.6**: 기본 작업 전반 (템플릿 편집, 스크립트 수정, 문서 작업)
- **Opus 4.7**: 아키텍처 결정, 보안 리뷰, `HARNESS-GUIDE.md` 수정, 다운스트림 영향 분석

---

## 시크릿 규칙

- `.env` 파일 복사 또는 커밋 절대 금지
- `cat .env` 금지 → 키 존재 확인은 `grep -c "KEY_NAME" .env`만 사용
- 터미널·대화창에 API 키값 노출 금지

---

## 참조

- [AGENTS.md](./AGENTS.md) — OMC 진입점 및 에이전트 목록
- [ARCHITECTURE.md](./ARCHITECTURE.md) — 시스템 아키텍처 전체 구조
- [skills/start-company/HARNESS-GUIDE.md](./skills/start-company/HARNESS-GUIDE.md) — 설계 결정 상세 근거
- [CHANGELOG.md](./CHANGELOG.md) — 버전별 변경 이력
