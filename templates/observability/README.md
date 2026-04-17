# Multi-Agent Observability — 설정 가이드

여러 에이전트가 동시에 실행될 때 무슨 일이 벌어지고 있는지 Discord 또는 Telegram으로
실시간 확인할 수 있는 PostToolUse 훅입니다.

---

## 왜 Observability가 필요한가

reddit r/ClaudeAI, r/aipromptprogramming 상위 10개 이슈 중 하나:
**"autonomous loop가 뭘 하고 있는지 모르겠다"**

ralph 루프나 agent-teams가 돌아가면 터미널을 붙잡고 있기 어렵습니다.
이 훅은 에이전트 활동(어떤 Tool을 호출했는지, 어떤 Task를 스폰했는지)을
외부 채널에 푸시해 CEO나 운영자가 모바일에서도 진행 상황을 파악할 수 있게 합니다.

참고 패턴: [disler/claude-code-hooks-multi-agent-observability](https://github.com/disler/claude-code-hooks-multi-agent-observability)

---

## 빠른 시작

### 1단계 — Webhook URL 발급

#### Discord Incoming Webhook
1. Discord 서버 → 채널 설정 → 연동 → 웹훅 → 새 웹훅
2. 이름 지정 후 "웹훅 URL 복사"
3. URL 형식: `https://discord.com/api/webhooks/{id}/{token}`

#### Telegram Bot
1. [@BotFather](https://t.me/BotFather) 에서 `/newbot` 실행 → 토큰 발급
2. 봇을 원하는 채팅/채널에 추가
3. `https://api.telegram.org/bot{TOKEN}/getUpdates` 로 `chat_id` 확인
4. URL 형식: `https://api.telegram.org/bot{TOKEN}/sendMessage?chat_id={CHAT_ID}`

### 2단계 — 환경변수 설정

```bash
# Discord (기본값)
export OBSERVABILITY_WEBHOOK_URL="https://discord.com/api/webhooks/YOUR_ID/YOUR_TOKEN"
export OBSERVABILITY_TYPE="discord"

# 또는 Telegram
export OBSERVABILITY_WEBHOOK_URL="https://api.telegram.org/botTOKEN/sendMessage?chat_id=CHAT_ID"
export OBSERVABILITY_TYPE="telegram"
```

`.env` 파일에 저장하거나 셸 프로파일(`~/.zshrc`, `~/.bashrc`)에 추가합니다.
**Webhook URL을 코드/파일에 하드코딩하지 마세요** — 항상 환경변수로만 주입합니다.

### 3단계 — PostToolUse 훅 등록

프로젝트의 `.claude/settings.json` 에 다음을 추가합니다:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Task|Stop|SessionStart",
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/observability-push.sh",
            "timeout": 8000
          }
        ]
      }
    ]
  }
}
```

`matcher` 패턴은 필터링 수준에 맞게 조정하세요 (아래 참조).

훅 파일은 `templates/hooks/observability-push.sh` 에서 복사합니다:

```bash
cp templates/hooks/observability-push.sh .claude/hooks/observability-push.sh
chmod +x .claude/hooks/observability-push.sh
```

---

## 필터링 수준 (OBSERVABILITY_FILTER_LEVEL)

| 수준 | 환경변수 값 | 어떤 이벤트를 푸시하는가 |
|------|------------|------------------------|
| 최소 | `minimal`  | Task 호출만 (에이전트 스폰 시점) |
| 일반 | `normal`   | Task + Stop + SessionStart (기본값) |
| 상세 | `verbose`  | 모든 PostToolUse 이벤트 |

```bash
# 기본값 (생략 시 normal 적용)
export OBSERVABILITY_FILTER_LEVEL="normal"

# ralph 루프 집중 모니터링 시
export OBSERVABILITY_FILTER_LEVEL="verbose"

# 핵심 에이전트 스폰만 보고 싶을 때
export OBSERVABILITY_FILTER_LEVEL="minimal"
```

> verbose 수준에서 트래픽이 많으면 Discord webhook rate limit(초당 5회)에
> 걸릴 수 있습니다. 장시간 루프는 `normal` 또는 `minimal` 권장.

---

## 보안 — 시크릿 마스킹

훅은 페이로드를 전송하기 전에 다음 패턴을 `[REDACTED]`로 교체합니다:

| 패턴 | 대상 |
|------|------|
| `AKIA[0-9A-Z]{16}` | AWS Access Key |
| `sk-[A-Za-z0-9]{20,}` | OpenAI / Anthropic API Key |
| `ghp_[A-Za-z0-9]{36}` | GitHub Personal Access Token |
| `xoxb-[0-9]+-...` | Slack Bot Token |
| `AIza[0-9A-Za-z_-]{35}` | Google API Key |
| `Bearer <token>` | Authorization 헤더 토큰 |
| 이메일 주소 패턴 | 개인정보 |
| `${VAR_NAME}` 형식 | 미치환 플레이스홀더 |
| `password=<value>` | 비밀번호 |

전체 마스킹 규칙은 `templates/observability/filter-rules.yaml` 참조.

**Webhook URL 자체도 절대 코드/커밋에 포함하지 마세요.**
환경변수 `OBSERVABILITY_WEBHOOK_URL`로만 주입하세요.

---

## 디버그 모드

```bash
# 네트워크 전송 없이 페이로드만 stderr에 출력
export OBSERVABILITY_DEBUG=1
```

이 모드에서는 curl을 호출하지 않고 구성된 JSON 페이로드를 stderr에 출력합니다.
설정 확인이나 페이로드 형태 검증에 사용합니다.

---

## 환경변수 요약

| 변수 | 필수 | 기본값 | 설명 |
|------|------|--------|------|
| `OBSERVABILITY_WEBHOOK_URL` | 필수 | (없음) | Discord 또는 Telegram webhook URL |
| `OBSERVABILITY_TYPE` | 선택 | `discord` | `discord` 또는 `telegram` |
| `OBSERVABILITY_FILTER_LEVEL` | 선택 | `normal` | `minimal` / `normal` / `verbose` |
| `OBSERVABILITY_DEBUG` | 선택 | `0` | `1`이면 전송 없이 stderr 출력만 |

---

## 아키텍처 노트

- **훅 타입**: PostToolUse 전용 (PreToolUse 절대 사용 금지 — v7.1 안전 불변성)
- **exit 0 보장**: 모든 오류(네트워크, 파싱, 환경변수 미설정)는 무시하고 항상 exit 0
- **타임아웃**: curl 5초 제한, settings.json timeout 8000ms (ralph 루프 차단 방지)
- **무한루프 방지**: `observability-push.sh` 자신의 호출은 자동으로 필터링
