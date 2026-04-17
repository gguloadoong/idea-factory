# Agent Teams 가이드

> **실험 기능 경고**: Agent Teams는 2026년 초 실험적으로 출시된 기능이다.
> API 및 동작 방식이 예고 없이 변경될 수 있다. 프로덕션 크리티컬 경로에는
> 사용 전 안정화 여부를 확인할 것.
> 공식 문서: https://code.claude.com/docs/en/agent-teams

---

## Agent Teams란 무엇인가

Agent Teams는 여러 Claude Code 세션이 하나의 팀으로 협력하는 기능이다.

- **팀 리드(Team Lead)**: 메인 Claude Code 세션. 팀을 생성하고 태스크를 배분하며 결과를 종합한다.
- **팀원(Teammates)**: 각자 독립된 컨텍스트 윈도우를 가진 별도의 Claude Code 인스턴스. 병렬로 작업한다.
- **공유 태스크 목록(Task List)**: 팀 전체가 공유하는 작업 큐. 팀원이 자율적으로 태스크를 클레임한다.
- **메일박스(Mailbox)**: 팀원 간 직접 메시지 시스템. 리드를 거치지 않고 팀원끼리 소통 가능.

기존 서브에이전트(subagent)와 달리, 팀원들은 서로 직접 메시지를 주고받으며
공유 태스크 목록을 통해 자율 조정한다.

---

## 활성화 방법

Agent Teams는 기본적으로 비활성화되어 있다. 두 가지 방법으로 활성화한다.

### 방법 1 — 환경변수 설정

```bash
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
```

### 방법 2 — settings.json에 추가 (권장)

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
```

Claude Code v2.1.32 이상이 필요하다. 버전 확인: `claude --version`

---

## 팀 생성 방법

설정 파일을 직접 작성하지 않는다. 팀은 **자연어 프롬프트로 생성**하며,
설정은 런타임에 `~/.claude/teams/{team-name}/config.json`에 자동 저장된다.

```text
Create an agent team using the web-app-team preset:
spawn a frontend-worker, backend-worker, and test-worker.
Use Sonnet for each teammate.
```

이 레포의 YAML 프리셋 파일(`web-app-team.yaml`, `cron-bot-team.yaml`)은
팀 리드가 참고하는 레퍼런스다. `suggested_lead_prompt` 섹션을 그대로 복사해
팀 리드 세션에 붙여넣으면 된다.

---

## 이 레포의 프리셋

| 파일 | 용도 | 워커 구성 |
|---|---|---|
| `web-app-team.yaml` | 웹 앱 MVP 병렬 빌드 | frontend + backend + test |
| `cron-bot-team.yaml` | 크론 봇 자동화 빌드 | logic + scheduler + monitoring |

각 워커는 기존 `templates/agents/` 단일 에이전트 정의를 `agent_type`으로 참조한다.
워커를 spawn할 때 해당 에이전트의 `tools` 허용 목록과 `model`이 적용되며,
에이전트 정의 본문이 팀원 시스템 프롬프트에 추가 지침으로 덧붙여진다.

---

## worktree 자동 분리

Agent Teams는 `isolation: "worktree"` 설정 시 각 팀원이
별도의 git worktree에서 작업하므로 파일 충돌이 원천적으로 방지된다.

프리셋에서는 `owned_paths` 방식으로 파일 소유권을 명시해 충돌을 예방한다.
동일 파일을 두 팀원이 편집하면 덮어쓰기 충돌이 발생하므로,
각 팀원이 고유 경로 집합만 편집하도록 spawn 프롬프트에 명시한다.

---

## 팀 리드의 역할

팀 리드는 다음을 담당한다:

1. **태스크 목록 생성**: 전체 작업을 자기완결적 단위로 분해한다 (팀원당 5-6개 권장)
2. **방향 결정**: 아키텍처 결정과 API 계약은 리드(Opus 권장)가 최종 확정
3. **품질 게이트**: 스키마·인증 변경 전 계획 승인 요청 (`plan approval`)
4. **합성**: 모든 팀원 완료 후 결과를 종합해 다음 단계로 전달
5. **정리**: 작업 완료 후 `Clean up the team`으로 팀 리소스 해제

---

## 언제 Agent Teams를 사용할 것인가

### 사용 권장

- **MVP 병렬화**: 프론트엔드와 백엔드가 서로 독립적으로 진행 가능한 경우
- **크로스 레이어 변경**: UI + API + 테스트가 각각 다른 파일 집합을 건드리는 경우
- **병렬 리뷰**: 보안, 성능, 테스트 커버리지를 동시에 다른 시각으로 검토할 때
- **경쟁 가설 디버깅**: 여러 팀원이 다른 이론을 독립적으로 검증할 때

### 순차 유지 권장

- **강한 커플링**: 팀원 A의 결과가 팀원 B의 입력인 경우 (병렬의 이점 없음)
- **동일 파일 편집**: 같은 파일을 여러 팀원이 건드려야 하는 경우
- **단순 반복 작업**: 조율 오버헤드가 이익보다 큰 소규모 작업
- **비용 민감 구간**: 팀원 수만큼 토큰이 선형 증가함을 고려

---

## 팀원 간 소통 방법

팀원은 두 가지 방식으로 소통한다:

- **message**: 특정 팀원 1명에게 직접 메시지
- **broadcast**: 모든 팀원에게 동시 전송 (비용이 팀 규모에 비례하므로 최소화)

사용자가 팀원에게 직접 메시지를 보내려면:

- **in-process 모드**: `Shift+Down`으로 팀원 전환 후 입력
- **split-pane 모드**: tmux/iTerm2에서 해당 팀원 창을 클릭 후 입력

---

## 현재 알려진 한계

Agent Teams는 실험 기능이므로 다음 제약이 있다:

| 제약 | 내용 |
|---|---|
| 세션 재개 불가 | `/resume`, `/rewind`가 in-process 팀원을 복원하지 못함 |
| 모델 고정 | 모든 팀원이 동일 모델을 사용 (개별 지정 불가, spawn 시 자연어로만 전달 가능) |
| 중첩 팀 불가 | 팀원이 하위 팀을 생성할 수 없음. 팀 리드만 팀 관리 가능 |
| 팀당 1개 | 세션 하나에 팀 하나만 운영 가능 |
| 태스크 상태 지연 | 팀원이 완료 마킹을 누락할 수 있음. 리드가 수동으로 nudge 필요 |
| split-pane 제약 | tmux 또는 iTerm2 필요. VS Code 통합 터미널, Windows Terminal 미지원 |

**모델 혼용이 필요한 경우**: 팀원은 현재 단일 모델로 제한된다.
Opus가 필요한 아키텍처 결정은 팀 리드(main session)에서 subagent로 처리한다.

---

## 비용 주의

팀원 수만큼 컨텍스트 윈도우가 독립적으로 열려 토큰 비용이 선형 증가한다.
3-5명이 대부분의 워크플로에 적합하다. 루틴 작업은 단일 세션이 더 비용 효율적이다.

---

## 다운스트림 적용

이 디렉터리의 파일은 `sync-manifest.json`에 `managed`로 등록되어 있다.
`sync-downstream.sh`로 10개 다운스트림 레포에 전파된다.
워커별 `spawn_prompt`의 `{{SERVICE_NAME}}` 플레이스홀더는
SCAFFOLD 단계에서 실제 서비스명으로 치환된다.
