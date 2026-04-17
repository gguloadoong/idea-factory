# Claude Code Routines — End-to-End Integration Guide
# Claude Code Routines — 통합 운영 가이드

> **Status / 상태**: Research preview (launched 2026-04-14). Schema and limits subject to change.
> **Reference**: https://code.claude.com/docs/en/routines

---

## Table of Contents / 목차

1. [What This Guide Covers](#what-this-guide-covers)
2. [Actor Diagram — idea-to-mvp flow](#actor-diagram)
3. [Setup: Prerequisites](#setup-prerequisites)
4. [Setup: Discord Webhook](#setup-discord-webhook)
5. [Setup: GitHub Configuration](#setup-github-configuration)
6. [Setup: Claude Account & Routine Creation](#setup-claude-account--routine-creation)
7. [Cost Model](#cost-model)
8. [Failure Modes & Retry Semantics](#failure-modes--retry-semantics)
9. [Security Checklist](#security-checklist)
10. [Korean Summary / 한국어 요약](#korean-summary)

---

## What This Guide Covers

This guide walks through the complete flow for the `idea-to-mvp` routine:
a CEO posts a one-line idea to a Discord channel, which triggers a GitHub Issue,
which fires a Claude Code Routine, which runs `/start-company`, creates a PR,
and posts the result back to Discord — all without opening a terminal.

The same pattern generalises to any event-driven automation on top of idea-factory.

---

## Actor Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                         idea-to-mvp flow                            │
└─────────────────────────────────────────────────────────────────────┘

  CEO (non-technical)
       │
       │  1. Types one-line idea into #아이디어 Discord channel
       ▼
  Discord Bot / GitHub Actions bridge
       │
       │  2. Creates GitHub Issue with label "idea"
       │     title: "고양이 SNS"
       ▼
  GitHub (repository event)
       │
       │  3. Issue-opened event fires
       │     → GitHub Actions workflow calls Routine API trigger
       ▼
  Claude Code Routine (Anthropic cloud)
       │
       │  4. New cloud session starts (no local machine needed)
       │     Prompt: "Read issue #N, run /start-company <idea>"
       │
       ├─ 4a. Clones repository
       ├─ 4b. Runs /start-company "고양이 SNS"
       │       └─ ANALYZE → SCAFFOLD → KICKOFF → BUILD MVP
       ├─ 4c. PR created on claude/idea-N branch
       └─ 4d. POST to DISCORD_WEBHOOK_URL with PR link
       │
       ▼
  Discord #아이디어 channel
       │
       │  5. Bot posts: "MVP scaffold ready for #42: 고양이 SNS — PR: <URL>"
       ▼
  CEO reviews PR
       │
       │  6. Approves or provides feedback in PR comments
       ▼
  (Subsequent runs handle VALIDATE → HARDEN → SHIP phases)
```

> **Note on GitHub Issues trigger**: As of the research preview, Routines support
> `pull_request` and `release` GitHub events natively. The Issues event is not yet
> available as a direct trigger. The recommended bridge is a lightweight GitHub Actions
> workflow (`.github/workflows/idea-routine-bridge.yml`) that fires on `issues.opened`
> with label `idea` and POSTs to the Routine's API trigger endpoint.
> See the workflow snippet in the Setup section below.

---

## Setup: Prerequisites

Before creating the routine, ensure the following are in place:

| Requirement | Where to configure |
|---|---|
| Claude Code on the web enabled | claude.ai > Settings > Claude Code |
| GitHub account connected to Claude | `/web-setup` in Claude CLI |
| Claude GitHub App installed on target repo | Prompted during routine creation |
| Discord server with a webhook-enabled channel | Discord channel settings |
| Claude plan: Pro / Max / Team / Enterprise | claude.ai > Settings > Billing |

---

## Setup: Discord Webhook

**Never hardcode the webhook URL in any file. Use environment variables only.**

### Step 1 — Create the webhook in Discord

1. Open Discord → target channel → **Edit Channel** → **Integrations** → **Webhooks**
2. Click **New Webhook**, give it a name (e.g. `idea-factory-bot`)
3. Click **Copy Webhook URL** — format: `https://discord.com/api/webhooks/<ID>/<TOKEN>`

### Step 2 — Store in Claude Cloud Environment

1. Go to `https://claude.ai/code/routines` → **Settings > Environments**
2. Select (or create) the environment for this routine
3. Under **Environment Variables**, add:
   - Key: `DISCORD_WEBHOOK_URL` / Value: the copied URL
   - Key: `GITHUB_TOKEN` / Value: a GitHub PAT with `repo` scope (or GitHub App token)
4. Save the environment

The routine prompt references `${DISCORD_WEBHOOK_URL}` — the value is injected at
runtime and never written to any file or log.

### Step 3 — Test the webhook manually

```bash
curl -X POST "${DISCORD_WEBHOOK_URL}" \
  -H "Content-Type: application/json" \
  -d '{"content": "idea-factory webhook test"}'
```

Expected: a message appears in the Discord channel.

---

## Setup: GitHub Configuration

### GitHub Actions bridge workflow

Since the Issues event is not yet a native Routine trigger, use this workflow
to bridge GitHub Issues → Routine API endpoint.

Save as `.github/workflows/idea-routine-bridge.yml` in the target repository:

```yaml
name: idea-routine-bridge

on:
  issues:
    types: [opened, labeled]

jobs:
  fire-routine:
    if: contains(github.event.issue.labels.*.name, 'idea')
    runs-on: ubuntu-latest
    steps:
      - name: Trigger idea-to-mvp routine
        run: |
          curl -X POST \
            "https://api.anthropic.com/v1/claude_code/routines/${{ secrets.IDEA_ROUTINE_ID }}/fire" \
            -H "Authorization: Bearer ${{ secrets.IDEA_ROUTINE_API_TOKEN }}" \
            -H "anthropic-beta: experimental-cc-routine-2026-04-01" \
            -H "anthropic-version: 2023-06-01" \
            -H "Content-Type: application/json" \
            -d "{\"text\": \"Issue #${{ github.event.issue.number }}: ${{ github.event.issue.title }}\"}"
```

Add two repository secrets in GitHub (Settings > Secrets and variables > Actions):
- `IDEA_ROUTINE_ID` — the routine ID from the URL at `claude.ai/code/routines/<ID>`
- `IDEA_ROUTINE_API_TOKEN` — generated in the Routine's API trigger modal (shown once)

### Branch protection

Routines push to `claude/`-prefixed branches by default. Ensure branch protection
rules on `main` do not block PR creation from `claude/*` branches.

---

## Setup: Claude Account & Routine Creation

### Option A — Web UI

1. Visit `https://claude.ai/code/routines` → **New routine**
2. **Name**: `idea-to-mvp`
3. **Prompt**: paste the prompt from `templates/routines/idea-to-mvp.yaml`
4. **Repository**: select the target repo; leave unrestricted pushes disabled
5. **Environment**: select the environment with `DISCORD_WEBHOOK_URL` configured
6. **Trigger**: choose **API** (the GitHub Actions workflow will call it)
7. After saving, open the routine → API trigger modal → **Generate token**
8. Copy the token immediately and store it as `IDEA_ROUTINE_API_TOKEN` in GitHub secrets

### Option B — CLI

```
/schedule idea-to-mvp: when triggered via API, read the issue number and idea
from the request text, run /start-company, open a PR, and POST the result to
the DISCORD_WEBHOOK_URL environment variable.
```

After `/schedule` creates the routine, add the API trigger and environment
variables from the web UI.

---

## Cost Model

### Which tier supports a burst of ideas?

Each routine run consumes one slot from the daily routine allowance AND draws
from the standard subscription usage (token cost of the Claude session).

| Scenario | Recommended tier | Reasoning |
|---|---|---|
| 1–5 ideas/day | **Pro** (5/day) | Exactly fits the limit; no overage |
| 6–15 ideas/day | **Max** (15/day) | Comfortable headroom |
| Team use, 15–25 ideas/day | **Team** (25/day) | Shared account; each member's runs count separately |
| Burst events (hackathon, launch day) | Any tier + **extra usage** | Enable in Settings > Billing; overage is metered |

### Token cost per run

A full `/start-company` run through ANALYZE + SCAFFOLD + KICKOFF + MVP phases
typically uses 200k–600k tokens (Sonnet 4.6 default, Opus for gate reviews).
At standard pricing this is $0.30–$1.50 per idea at list rates.
Enable extra usage for predictable cost; monitor at `claude.ai/settings/usage`.

### GitHub Actions cost

The bridge workflow runs on `ubuntu-latest` and completes in under 10 seconds
(single curl call). At GitHub's free tier (2,000 min/month on public repos,
2,000 min on private), this adds negligible cost.

---

## Failure Modes & Retry Semantics

### Routine-level failures

| Failure | Cause | Resolution |
|---|---|---|
| Run rejected at trigger time | Daily cap reached | Enable extra usage, or wait for midnight reset |
| GitHub App not installed | Webhook delivery fails silently | Install Claude GitHub App via routine edit form |
| API token expired / revoked | 401 from `/fire` endpoint | Regenerate token in routine's API trigger modal |
| Routine times out mid-session | Very long `/start-company` run | Add explicit checkpoints in prompt; split into phases |

### Retry semantics

Routines do **not** automatically retry a failed run. Each trigger event starts
exactly one session. If a run fails:

1. Check the session log at `claude.ai/code/routines` → click the failed run
2. Identify the failure point (network error, token cost cap, tool failure)
3. Click **Run now** on the routine detail page to manually re-trigger
4. Or re-open / re-label the GitHub Issue to re-fire the GitHub Actions bridge

### `/start-company` circuit breaker

If the inner `/start-company` session hits the fix-loop circuit breaker
(same story fails 3 times), it escalates to the CEO. In a Routine context this
means the session will write a `decisions.md` entry and stop. Check the session
log for the escalation message and intervene manually.

### Discord webhook failures

If `DISCORD_WEBHOOK_URL` is missing or the POST fails, the Routine session will
log the error but the PR is still created. The routine prompt should treat the
Discord notification as best-effort, not a blocking requirement.

---

## Security Checklist

- [ ] `DISCORD_WEBHOOK_URL` stored only in Claude Cloud Environment, not in any file
- [ ] `GITHUB_TOKEN` stored only in Claude Cloud Environment; minimum scope (`repo`)
- [ ] `IDEA_ROUTINE_API_TOKEN` stored only in GitHub Actions secret; never in code
- [ ] `IDEA_ROUTINE_ID` is not sensitive (it is a public identifier) but keep it in secrets for hygiene
- [ ] Routine scope limited: only the target repository is attached
- [ ] Connectors list trimmed: only `github` connector enabled for this routine
- [ ] Branch push restricted to `claude/*` prefix (default; do not disable)
- [ ] API token rotated if ever exposed: **Regenerate** in routine's API trigger modal
- [ ] Claude GitHub App granted minimum repository access (single repo, not all repos)
- [ ] OAuth 2.1 flow: Claude's GitHub identity uses short-lived tokens per session

---

## Korean Summary

### 전체 흐름 요약

1. **대표**: Discord `#아이디어` 채널에 한 줄 아이디어 입력
2. **Discord → GitHub 브릿지**: GitHub Issue 자동 생성 (라벨: `idea`)
3. **GitHub Actions**: Issue 오픈 이벤트 감지 → Routine API trigger 호출
4. **Claude Code Routine** (Anthropic 클라우드):
   - 새 세션 시작 — 로컬 머신 불필요
   - `/start-company "<아이디어>"` 실행
   - ANALYZE → SCAFFOLD → KICKOFF → MVP 단계 자동 진행
   - PR 생성 → Discord webhook POST
5. **대표**: Discord에서 PR 링크 수신 → 검토·승인

### 설정 체크리스트

- [ ] Claude Code on the web 활성화 (`claude.ai > Settings > Claude Code`)
- [ ] GitHub 연결 (`/web-setup` in CLI)
- [ ] Discord Incoming Webhook URL 발급 후 Claude Cloud Environment에 등록
- [ ] GitHub Actions 브릿지 워크플로우 배포 (`.github/workflows/idea-routine-bridge.yml`)
- [ ] Routine 생성 후 API 토큰 → GitHub Actions secret 등록
- [ ] 테스트: Issue 등록 → Discord 알림 확인

### 요금 가이드

- 하루 5건 이내: Pro 충분
- 하루 6–15건: Max 권장
- 팀 운영 또는 폭발적 아이디어 기간: Team + extra usage 활성화

### 관련 파일

- `templates/routines/idea-to-mvp.yaml` — 루틴 설정 레퍼런스
- `templates/routines/README.md` — 한국어 빠른 시작 가이드
- `ARCHITECTURE.md` — Routines 아키텍처 섹션
