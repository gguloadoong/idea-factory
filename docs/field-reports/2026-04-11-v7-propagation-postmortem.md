# Field Report: v7 Propagation Incident Postmortem

**Date**: 2026-04-11
**Incident window**: 2026-04-04 (v7 release) → 2026-04-09 (user report) → 2026-04-11 (v7.1 hotfix)
**Severity**: High (blocked downstream autonomous workflows)
**Resolution**: v7.1 hotfix released, all affected projects either self-healed or unaffected

---

## 요약

idea-factory `start-company v7` (commit `e61f0af`, 2026-04-04) 가 추가한 `PreToolUse` Bash 훅이 다운스트림 프로젝트(market-dashboard-v5 등)에 전파되면서, 모든 Bash 명령마다 승인 프롬프트를 유발해 autopilot/ralph 등 자율 워크플로우를 **마비**시킨 회귀 사건.

## 타임라인

| 날짜 | 사건 |
|---|---|
| 2026-04-04 | `start-company v7` 릴리스 (commit `e61f0af`). `templates/settings.json` 에 `check-careful.sh`, `check-safety.sh`, `check-gate-isolation.sh` 세 개의 PreToolUse 훅 추가. 의도: 위험 명령 + 13개 안전 규칙 + 게이트 격리 강제. |
| 2026-04-04 ~ 4-08 | v7 이 market-dashboard-v5 등 다운스트림 프로젝트에 전파됨. |
| 2026-04-09 | 사용자가 Claude Code 세션에서 보고: **"마켓레이더 v5 작업하는 터미널에서 이게 자꾸 떠, 어제 start company v7 적용시키고부터야"** |
| 2026-04-10 | 원인 진단 시작. PreToolUse 블로킹 훅이 모든 Bash 명령에 대해 사용자 승인을 요구하는 것으로 확인. |
| 2026-04-11 | v7.1 hotfix 시작. Issue #2, PR #3, 컨센서스 게이트(code-reviewer + critic), docs 정리 후 `docs/plans/v8-backlog.md` 기반의 후속 학습 레이어 구축. |

## 기술적 원인

`templates/settings.json` 이 포함한 v7 훅 구성:

```json
"PreToolUse": [
  {
    "matcher": "Bash",
    "hooks": [
      { "command": "bash .claude/hooks/check-careful.sh", "timeout": 5000 },
      { "command": "bash .claude/hooks/check-safety.sh", "timeout": 5000 }
    ]
  },
  {
    "matcher": "Agent",
    "hooks": [
      { "command": "bash .claude/hooks/check-gate-isolation.sh", "timeout": 5000 }
    ]
  }
]
```

**블로킹 동작**: 이 훅들이 모든 Bash/Agent 호출 직전에 실행되고, exit non-zero 반환 시 Claude Code 가 사용자 승인을 요구. 자율 실행 루프는 사용자 승인이 없으면 진행 못 함 → halt.

**설계 의도 vs. 현실**:
- **의도**: 위험 명령(`rm -rf`, `sudo`, force push) + 크리덴셜 노출 차단 + 게이트 격리 강제
- **현실**: 훅이 지나치게 공격적으로 설계됨. 벙어 `git status`, `ls`, `npm run build` 같은 루틴 명령도 검토 대상에 포함되어, 실질적으로 모든 명령이 승인을 요구

## v7.1 해결책

### 즉시 수정 (`templates/settings.json`)
- `PreToolUse: []` (블로킹 훅 전부 제거)
- `permissions.allow` 화이트리스트 제거
- `defaultMode: "bypassPermissions"` 채택
- `permissions.deny` 유지 — 재해복구 불가능한 것만:
  - `Bash(rm -rf /)`, `Bash(rm -rf ~)`, `Bash(sudo *)`
  - `Read(.env*)`, `Read(**/credentials*)`, `Read(**/*secret*)`
- `PostToolUse` (Write/Edit → CLAUDE.md 크기 체크) 유지

### 후속 정리
- `templates/hooks/check-safety.sh`, `check-gate-isolation.sh` 고아 파일 삭제
- `templates/hooks/check-careful.sh` 는 미래 exit-0 advisory 재설계용으로 유지
- `skills/start-company/SKILL.md:71` 의 `check-safety.sh` 스캐폴드 스텝 삭제 + 번호 재매김
- `HARNESS-GUIDE.md` "Runtime Safety Hooks" Design Decision 섹션을 v7.1 현실에 맞게 재작성
- `HARNESS-GUIDE.md` 아키텍처 다이어그램 훅 리스트 업데이트
- `README.md` "What's New" v6.1 → v7.1 동기화
- `HARNESS-GUIDE.md` Changelog 에 v7.1 엔트리 추가

### 배포
- `v7.1` git tag 생성 + 푸시
- [GitHub Release](https://github.com/gguloadoong/idea-factory/releases/tag/v7.1) 작성

## 다운스트림 영향 범위

스캔 결과, **실제로 v7 회귀 패턴이 남아있는 프로젝트는 0개**:

| 프로젝트 | 상태 | 비고 |
|---|---|---|
| market-dashboard-v5 | ✅ 자가 치유 완료 | 원래 보고 사이트. Bash 훅 제거, `bypassPermissions` 적용, `deny` v7.1 일치 |
| reel-forge | ✅ 깨끗 | `bypassPermissions` 이미 적용 |
| bias-today | ✅ 깨끗 | v7 훅 없음 |
| cashfreel, grow-money | ✅ 깨끗 | 24줄 심플 |
| chimp-pick, trend-pulse, sobi-type | ✅ 깨끗 | v7 훅 없음 |
| trading-signal-bot | N/A | `.claude/settings.json` 자체가 없음 |

**의미**: v7.1 릴리스는 향후 새 프로젝트와 v7 템플릿을 신규 복사할 사용자에게 유효. 기존 프로젝트는 이미 수동 치유되었거나 애초에 v7 훅을 받지 않은 상태.

## 근본 원인 분석

**표면 원인**: 훅이 너무 공격적으로 설계됨 (blocking behavior).

**구조적 원인**: **블로킹 PreToolUse 훅은 장기 자율 루프와 근본적으로 양립 불가능**. autopilot/ralph 같은 워크플로우는 인간 개입 없는 연속 실행을 전제로 설계되었는데, 이 전제를 `check-careful.sh` 등이 깨뜨림.

**메타 원인**: idea-factory 는 **새 기능이 기존 자율 실행 워크플로우와 어떻게 상호작용하는지 검증할 메커니즘이 없었음**. v7 릴리스 전에 한 개라도 실제 프로젝트에서 autopilot 한 사이클을 돌려봤다면 즉시 발견되었을 문제.

## 교훈

### 즉각 적용 (이미 함)
1. **Blocking PreToolUse 훅 금지** — idea-factory 에서 영구 규칙화. `HARNESS-GUIDE.md` + 메모리 시스템(`feedback_pretooluse_hooks.md`) 에 명시.
2. **deny-list + bypassPermissions 가 자율 실행의 올바른 runtime safety floor** — 블로킹이 아니라 narrow deny 로.
3. **재해복구 불가능한 것만 deny** — `rm -rf /`, `sudo`, 시크릿 읽기. 회복 가능한 위험 작업(force push, `--hard` reset) 은 CLAUDE.md 룰 + 코드 리뷰로 관리.

### v8 backlog 로 편입 (아직 안 함)
1. **Exit-0 audit-log PreToolUse 훅** — 블로킹 아닌 로깅 전용. `HARNESS-GUIDE.md:196` 이 shelved 한 작업. v8 backlog item **1.1**.
2. **템플릿 변경 후 자율 루프 검증 의무화** — v7 같은 회귀를 사전에 catch 하려면 릴리스 전에 실제 프로젝트에서 한 사이클 돌려봐야 함. 프로세스 변경 필요.
3. **Rule-driven deny-list per project type** — trading bot 에는 `vercel --prod` 추가 필요, 결제에는 `stripe *` 추가 등. v8 backlog item **1.3**.

### 외부 검증
외부 리서치(`docs/research/2026-04-11-tsb-harness-external.md`) 에 따르면 이 교훈 — **"블로킹 PreToolUse 훅은 자율 루프와 양립 불가"** — 은 문헌 코퍼스에서 **가장 battle-tested 된 harness engineering 발견**. HumanLayer 와 Anthropic 이 독립적으로 동의하며, idea-factory 자체가 이제 1차 증거 (primary source) 로 인용 가능.

## 참조

- Issue: https://github.com/gguloadoong/idea-factory/issues/2
- PR: https://github.com/gguloadoong/idea-factory/pull/3
- Release: https://github.com/gguloadoong/idea-factory/releases/tag/v7.1
- Changelog entry: `skills/start-company/HARNESS-GUIDE.md#changelog` (v7.1)
- Memory: `.claude/projects/-Users-bong-idea-factory/memory/feedback_pretooluse_hooks.md`
- v8 backlog items derived: 1.1, 1.3, 1.4
