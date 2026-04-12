# Vercel 과금 사건 — 템플릿 전파 실패

**날짜**: 2026-04-13
**심각도**: 실비용 발생 (Vercel Pro 추가 과금)
**근본 원인**: idea-factory 템플릿 → 다운스트림 프로젝트 동기화 메커니즘 부재

## 사건 요약

사용자가 Vercel Pro 추가 요금 발생 보고. 조사 결과 10개 레포 중 7개에서 `vercel.json` 설정이 불완전하여 불필요한 preview deployment가 대량 생성/실행됨.

## 발견된 문제 유형

| 유형 | 레포 | 영향 |
|---|---|---|
| ignoreCommand 완전 누락 | trading-signal-bot, bull-vs-bear | 모든 preview 빌드 실행 |
| ignoreCommand 문법 오류 (`[` 뒤 공백 누락) | costock | 조건 항상 실패 → 모든 빌드 실행 |
| `exit 1` 누락 (production도 스킵) | signalplay, chimp-pick, aptner | production 배포도 안 됨 |
| git.deploymentEnabled 미설정 | 전체 (idea-factory 포함) | 매 push마다 deployment record 생성 |

## 고활동 레포 (과금 주범)

- signalplay: 100+ PRs
- chimp-pick: 50 PRs  
- market-dashboard-v5: 47 PRs

## 근본 원인 분석

```
idea-factory templates/vercel.json 개선
        ↓
새 프로젝트에만 적용
        ↓
기존 8개 프로젝트는 구 버전 vercel.json 유지
        ↓
AI 워크플로우가 PR 대량 생성
        ↓
preview deployment 폭증 → 추가 과금
```

**핵심**: idea-factory에 "템플릿 업데이트 → 다운스트림 전파" 메커니즘이 전혀 없음.
이건 vercel.json만의 문제가 아님 — settings.json, hooks/, CLAUDE.md 전부 같은 취약점.

## 수정 조치

### 즉시 (2026-04-13 적용)
1. 7개 레포 ignoreCommand 추가/수정
2. 8개 레포 git.deploymentEnabled 추가 (main만 deployment)
3. idea-factory templates/vercel.json 강화
4. SKILL.md에 Vercel Preview Deployments OFF 안내 추가

### 구조적 (v8-backlog 7.4로 등록)
- `scripts/sync-downstream.sh` 개발 필요
- `.idea-factory-version` 추적 파일 도입
- drift 감지 + 자동 PR 생성

## 교훈

1. **스캐폴드는 한 번, 버그는 N번**: 템플릿 버그의 blast radius = 스캐폴드된 프로젝트 수
2. **AI 대량 PR 시대에 preview deployment는 비용 폭탄**: 과거 수동 PR 시절에는 괜찮았지만 AI가 PR을 쏟아내면 다름
3. **exit 0/1 의미를 정확히 알아야 함**: Vercel ignoreCommand에서 exit 0 = skip, exit 1 = build — 직관과 반대
4. **전파 없는 템플릿은 스냅샷**: 개선해도 과거에는 안 퍼짐. sync 메커니즘이 first-class여야 함
