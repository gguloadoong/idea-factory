# Changelog

All notable changes to idea-factory are documented here.
Format follows [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/).

---

## [Unreleased]

### Added (shipped to main, awaiting v8.2 tag)
- `.github/workflows/sync-downstream.yml` + `docs/sync-downstream-workflow.md` — 다운스트림 sync를 GitHub Actions `workflow_dispatch`로 실행 (#38). 수동 트리거 + dry-run 기본 + PAT 기반 권한 격리.
- Scaffold completeness 수정 (#36) — install.sh가 `cp -R templates/.` 전체 복사로 변경, phases.md SCAFFOLD에 5개 optional extension 디렉터리 명시.

### Planned (not yet shipped)
- v8 item 1.4: JSONL audit log grep tooling for session misbehavior analysis
- 다운스트림 sync 자동 트리거 (v2: 템플릿 변경 머지 시 자동 check 모드)
- 샘플 MVP 갤러리 실제 결과물 수록
- 데모 비디오 3종 (5분 MVP / 음성+Routines 트리거 / 한국어 자율 에이전트)

---

## [v8.1] — 2026-04-17

**Plugin Marketplace Ready**. Claude Code 2026-Q1 생태계 통합 + 공개 레포 거버넌스 완비 + 다국어 문서.

PR 7건 (#25 · #26 · #27 · #32 · #33 · #34 · #35) + main 직접 커밋 12건.

### Added

**루트 거버넌스 (공개 레포 표준)**
- `LICENSE` (MIT) — README 뱃지와 실제 파일 정합
- `CLAUDE.md`, `AGENTS.md`, `ARCHITECTURE.md` — 자기 자신 dogfooding
- `CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md`
- `.github/ISSUE_TEMPLATE/{bug_report,feature_request,template_change,config}.yml`
- `.github/PULL_REQUEST_TEMPLATE.md`

**Claude Code 2026-Q1 생태계 통합**
- **Skills 2.0** (#22): `skills/start-company/SKILL.md` 17KB → 3.1KB 분할 + `phases.md` + `agents.md` + `allowed-tools` frontmatter (progressive disclosure)
- **`.claude/rules/` 패턴** (#23): `templates/.claude/rules/` 스캐폴드 (commit / security / code-style / ai-regression) + `@import` opt-in
- **MCP 번들** (#24): `templates/mcp/` — Supabase + Vercel 프리셋, OAuth 2.1 + RFC 8707 Resource Indicators
- **Plugin Marketplace** (#28): `.claude-plugin/plugin.json` + 마켓 리스팅 README + 제출 체크리스트
- **Routines** (#29): `templates/routines/` — 2026-04-14 출시 클라우드 자동화 참고 템플릿 + 디스코드 웹훅 브릿지 가이드
- **Agent Teams** (#30): `templates/agent-teams/` — web-app / cron-bot 3-워커 프리셋 + `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` 활성화
- **Multi-agent Observability** (#31): `templates/hooks/observability-push.sh` (PostToolUse, exit-0) + Discord / Telegram 푸시 + 8종 시크릿 마스킹

**문서 확장**
- `CHANGELOG.md` — Keep-a-Changelog 1.1.0 포맷 독립 파일 (HARNESS-GUIDE 내부에서 분리)
- `docs/README.md` — docs/ 디렉터리 인덱스
- `docs/ko/README.md` — 영어 수준으로 확장 (2.8 KB → 16.5 KB, 15 섹션 한국어화)
- `docs/plugin-submission-checklist.md` — 공식 + 커뮤니티 마켓플레이스 제출 절차
- `docs/routines-integration.md` — 디스코드 → Routine → PR end-to-end 가이드 (318줄 한·영)
- `docs/awesome-list-entry.md` — 5종 awesome-list 제출 초안
- `examples/README.md` — 샘플 MVP 갤러리 수록 기준 + 기여 템플릿
- `ARCHITECTURE.md` "Claude Code 2026-Q1 Integrations" 섹션: 1M context / /rewind / Opus 4.7 토크나이저 / Routines / Agent Teams / Observability / .claude/rules / MCP Bundles

### Changed

- `install.sh` 모델 버전 갱신: `claude-opus-4-6` → `claude-opus-4-7` (2026-04-16 출시)
- `README.md` "What's Inside" 트리 — 실제 `templates/` 구조 반영 (10+ 누락 항목 복구, Core / Advanced 구분)
- `templates/CLAUDE.md.tmpl` 최하단에 `@.claude/rules/*.md` 주석 처리 opt-in 예시 추가 (80-줄 제약 유지)
- `sync-manifest.json`: +14 managed entries (rules / mcp / routines / agent-teams / observability)
- `.claude-plugin/plugin.json` version: `8.0.0` → `8.1.0`

### Removed

- `templates/agents/*.md.bak` 3종, `templates/documents/*.tmpl.bak` 2종, `templates/hooks/*.sh.bak*` 3종 — 원본과 SHA 동일한 순수 중복
- `docs/plans/v8-backlog.md`, `docs/field-reports/` — 내부 기획·인시던트 포스트모템을 비공개 로컬 저장소로 이전
- Stale merged feature branches 5개 원격 정리

### Security

- `LICENSE` 파일 명시 — GitHub API `license` 필드 `null` 상태 해소
- `.gitignore` 확장: `*.bak`, `*.bak.*`, `*.tmp` — 백업 파일 재발 방지
- MCP 프리셋: OAuth 2.1 + PKCE + Resource Indicators (RFC 8707) 기본 — 하드코딩 API 키 0건
- Observability 훅: PostToolUse 전용 (exit 0 invariant 3중 보호) + 8종 시크릿 마스킹 (AWS / sk- / ghp_ / xoxb- / AIza / Bearer / password / email / placeholder)
- **git filter-repo로 docs/plans + docs/field-reports를 전체 히스토리에서 완전 삭제** — git log 조회로도 노출 불가

### GitHub Repository Meta

- `license`: `null` → `MIT`
- `is_template`: `false` → `true` (**Use this template** 버튼 활성화)
- `topics`: `[]` → `ai-agents · autonomous-builder · claude-code · korean · llm-orchestration · mvp-generator · startup-factory · template-repository`
- `homepage`: `null` → `https://github.com/gguloadoong/idea-factory#install`
- Repository description 최신화

---

## [v8] — 2026-04-13

v8 백로그 27개 항목 전체 완료 (100%). Wave 1부터 7.4까지.

### Added
- **Loop breaker hook** (item 1.1 wave 1): 동일 실패 3회 반복 시 자동 중단 + 에스컬레이션 (`check-audit.sh` — exit-0 audit log, 유일한 PreToolUse Bash 훅)
- **Decay counter** (item 1.2 wave 1): 반복 패턴 감지 카운터 — 루프 탈출 조건 수치화
- **Learning capture hook** (item 1.3 wave 1): 세션 종료 시 학습 내용 자동 기록
- **Project-type deny-list extensions** (item 1.3): 프로젝트 타입별(SaaS/스크립트/내부툴) 맞춤 deny-list 확장 규칙 (#16, #18)
- **Numerical tuning harness** (item 5.1): 수치 파라미터(타임아웃, 재시도 횟수 등) 조정용 harness
- **Cron-bot template** (item 5.2): 스케줄 기반 봇 프로젝트 스캐폴드 (#19)
- **Config protection hook** (item 7.3): 설정 파일 약화 감지 — `settings.json` / `CLAUDE.md` 핵심 보호 규칙이 삭제되면 경고 (#11)
- **Template-to-downstream sync mechanism** (item 7.4): `sync-lib.py` — idea-factory 템플릿 변경을 다운스트림 프로젝트에 자동 전파 (#20, #21)
- **SessionStart PR 감지 훅**: 세션 시작 시 미처리 PR 알림
- **Vercel preview 배포 비활성화**: 템플릿에 `vercel.json` preview 차단 설정 추가 (과금 방지)

### Fixed
- `sync-lib.py`: 라벨 없는 레포에서 PR 생성 실패 수정
- `create-pr.sh`: market-dashboard-v5 수준으로 업데이트 (라벨/리뷰어/본문 포맷 일관성)

### Changed
- GitHub 브랜치 보호 규칙을 market-dashboard-v5 수준으로 강화

---

## [v7.1] — 2026-04-11

v7에서 도입한 PreToolUse 훅이 다운스트림 프로젝트의 자율 워크플로우를 마비시킨 회귀를 수정.

### Fixed
- `check-careful.sh`, `check-safety.sh` (Bash PreToolUse), `check-gate-isolation.sh` (Agent PreToolUse) 제거 — 모든 Bash 명령마다 승인 프롬프트를 유발, `ralph` / `autopilot` 루프 사실상 불능 (#2, #3)

### Changed
- `templates/settings.json`: `PreToolUse: []` (비움), `permissions.allow` 화이트리스트 제거
- `defaultMode: "bypassPermissions"` 로 전환 — 자율 실행 레포 기본값
- `permissions.deny` 유지: `rm -rf /`, `sudo *`, `.env*`, credentials, secrets 패턴
- `PostToolUse` CLAUDE.md 크기 체크 훅 유지

### Removed
- `check-careful.sh`, `check-safety.sh`, `check-gate-isolation.sh` PreToolUse 훅

> 교훈: 자율 실행 레포의 PreToolUse 훅은 **exit 0 로깅 전용**이어야 함. Blocking 훅은 autopilot/ralph 워크플로우와 근본적으로 양립 불가.

---

## [v7] — 2026-04-07

market-dashboard-v5의 13 phases / 200+ PRs에서 검증된 11개 패턴을 idea-factory에 이식.

### Added
- **Quality Ratchet**: `.project/quality-baseline.md` — 품질 지표는 올라가기만 하고 내려갈 수 없음
- **Protected Files**: `.protected-files` + `run-architect.sh` — 핵심 로직 변경 시 Opus 리뷰 강제
- **5-Stage PR Pipeline**: `create-pr.sh` — build → code-reviewer → Codex gate → auto issue linking → bot 폴링
- **6-Gate Deploy Consensus**: `pre-deploy-consensus.sh` — build / P0·P1 / PM / QA / dev / final sign-off 6단계
- **Nonce-based prompt injection prevention**: PM 리뷰 게이트에서 프롬프트 주입 방지
- **Review Summary**: `review-summary.sh` — 리뷰 결과 자동 PR 코멘트 포스팅
- **Doc Auto-Update**: `update-project-docs.sh` — PR 시 CONTRACT.md / decisions.md / README 자동 동기화
- **Git Hooks**: `.githooks/pre-push` — 오래된 리뷰 경고 (soft gate)
- **Token Health**: `.github/workflows/token-health.yml` — 주간 배포 토큰 유효성 검사
- **CONTRACT.md FAQ 패턴**: "왜 X가 제거됐나요?" — zombie component 부활 방지
- **Agent depth guidance**: 에이전트당 50줄 이상 경력 앵커 + 협업 규칙
- **새 스토리**: HARDEN-005/006, SHIP-003/004/005 (강화된 Ship 파이프라인)

---

## [v6.1] — 2026-04-02

커뮤니티 리서치 + 실제 프로젝트(market-dashboard-v5) 통합.

### Added
- **4번째 리뷰어**: `code-reviewer` (global Opus agent, 2-stage review) — 3 → 4 리뷰어 게이트 확장
- **Codex Gate**: `codex-review-gate.sh` — 크로스 모델 리뷰 (OpenAI Codex CLI)
- **CLAUDE.md 80줄 제한**: AI 명령 준수율은 ~150줄 이상에서 급락 (HumanLayer 리서치 기반)
- **Fix-loop 3회 circuit breaker**: 동일 실패 3회 → 즉시 CEO 에스컬레이션
- **Ghost Bug 인식**: 문서화된 알려진 회귀 패턴 가이드

### Changed
- **스코어링 정책 수정**: "점수 없음" → "결함 먼저 / 점수 두 번째 (two-pass)" — Evaluator Leniency 수정
- **PR 파이프라인**: SHIP-002가 `npm run pr` 체인 설정 (build → code-reviewer → Codex gate → PR → bot review)

### Fixed
- YAML tools 포맷, 훅 타임아웃, `$ARGUMENTS` 참조 오류 수정 (agnix linting)

---

## [v6] — 2026-04-02

harness 엔지니어링 1차 오버홀.

### Changed
- 게이트 리뷰: 점수 기반 → 결함 탐지 프레이밍 (Evaluator Leniency 수정)
- 게이트 리뷰어: 동일 컨텍스트 → 격리된 worktree (Fresh Context)
- qa-tester: 코드 리뷰 전용 → Playwright MCP 실브라우저 테스트
- Phase 전환: 암묵적 → 구조화된 handoff 문서
- Safety: 기본 위험 명령 체크 → 8-rule 런타임 가드레일
- Essence 검증: 수치 drift 점수 → 적대적 질문 방식

### Removed
- PRD 템플릿에서 "score >= 7/10" 성공 기준 제거

---

## [v5] — 2026-03-26

MVP-First 재설계. Ralph 상태머신 도입. 템플릿 기반 스캐폴딩.

### Added
- MVP 3-Phase 구조: Prototype → Harden → Ship (실제 API는 Phase 2부터)
- Ralph 상태머신을 빌드 루프 백본으로 채택
- 템플릿 기반 스캐폴딩 (`templates/` 디렉토리) — 컨텍스트 낭비 없이 프로젝트 생성
- `essence.md` North Star 문서 — 기능 drift 감지용

---

[Unreleased]: https://github.com/gguloadoong/idea-factory/compare/v8.1.0...HEAD
[v8.1]: https://github.com/gguloadoong/idea-factory/releases/tag/v8.1.0
