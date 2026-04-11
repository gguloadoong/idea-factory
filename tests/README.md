# idea-factory tests

## 목적

idea-factory 의 훅, 스크립트, 템플릿이 회귀 없이 작동하는지 자동 검증.

## 가장 중요한 불변식

**모든 `templates/hooks/*.sh` 는 입력에 관계없이 exit 0 을 반환해야 한다.**

이 규칙은 v7 회귀 (2026-04) 에서 배운 것이다. 블로킹 PreToolUse 훅이 사용자 승인 프롬프트를 유발해 다운스트림 자율 워크플로우를 마비시켰다. v7.1 이후 idea-factory 의 런타임 safety 모델은 **"관측하되 차단하지 않음"** — 진짜 금지해야 할 것은 `permissions.deny` 가 담당, 훅은 exit 0 로깅만.

`tests/invariant-exit-zero.sh` 가 이 불변식을 기계적으로 검증한다. 이 테스트는 `templates/hooks/` 의 모든 `.sh` 파일에 다양한 입력 (정상 JSON, 빈 문자열, malformed JSON, binary garbage, 1MB 거대 입력) 을 넣고 전부 exit 0 인지 확인한다. 하나라도 non-zero 면 CI 실패.

## 구조

```
tests/
├── README.md              # 이 파일
├── run-all.sh             # 모든 테스트 실행
├── invariant-exit-zero.sh # v7 회귀 방지 가드
└── hooks/
    └── <hook-name>.test.sh
```

각 훅마다 `tests/hooks/<hook-name>.test.sh` 를 작성한다. 이 파일은 self-contained 하고 exit 0 시 pass, non-zero 시 fail.

## 로컬 실행

```bash
bash tests/run-all.sh
```

모든 테스트 통과 시 exit 0, 하나라도 실패 시 exit 1 + 실패 목록 출력.

## CI 실행

`.github/workflows/ci.yml` 이 `templates/hooks/**` 또는 `tests/**` 가 변경되는 PR 마다 자동 실행.

## 새 훅 추가 시

1. `templates/hooks/<name>.sh` 작성 (exit 0 불변식 엄수: `trap 'exit 0' ERR EXIT`, 명시적 `exit 0`, 모든 외부 호출에 fallback)
2. `tests/hooks/<name>.test.sh` 작성 (정상 케이스 + 엣지 케이스)
3. `bash tests/run-all.sh` 로 로컬 통과 확인
4. PR 열기

`tests/invariant-exit-zero.sh` 는 자동으로 새 훅을 발견하므로 추가 작업 없음.

## 관련 문서

- `skills/start-company/HARNESS-GUIDE.md` — v7.1 Runtime Safety 설계 근거
- `docs/field-reports/2026-04-11-v7-propagation-postmortem.md` — v7 회귀 사건 정리
- `docs/plans/v8-backlog.md` Theme 1 — Runtime Safety v8 backlog
