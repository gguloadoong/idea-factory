# MCP 번들 — Supabase + Vercel 프리셋

## 왜 MCP 번들?

MCP(Model Context Protocol)는 Claude Code가 외부 서비스(DB, 배포 플랫폼 등)를
직접 제어할 수 있게 해주는 표준 프로토콜이다.
이 번들을 활성화하면 Claude가 Supabase 스키마 조회, 마이그레이션 실행,
Vercel 배포 상태 확인 등을 터미널 없이 수행할 수 있다.
Lovable/Bolt 수준의 "아이디어 → 배포" 자동화의 시작점이 여기다.

---

## 왜 OAuth 2.1?

### 하드코딩 API 키 방식 (나쁨)
```json
{ "env": { "SUPABASE_ACCESS_TOKEN": "sbp_abc123..." } }
```
- 키가 파일에 남는다 → git 커밋 실수 시 영구 노출
- 키 만료·로테이션 시 수동 갱신 필요
- 공격 표면이 넓다

### OAuth 2.1 브라우저 승인 방식 (권장)
```
Claude Code 실행 → 브라우저 팝업 → 사용자가 직접 승인 → 단기 토큰 자동 발급
```
- 장기 토큰을 파일에 저장하지 않는다
- RFC 8707 Resource Indicators 구현: 토큰이 특정 서버에만 유효
- 토큰 만료 시 자동 재승인 (사용자 개입 최소화)
- 이 프리셋의 `${SUPABASE_ACCESS_TOKEN}`, `${VERCEL_API_TOKEN}` 자리표시자는
  런타임에 환경변수로 주입되며, 파일 자체에는 실제 값이 들어가지 않는다

---

## 설치법

### 1단계 — 프리셋을 프로젝트 settings.json에 병합

`merge-example.sh`를 참고하거나 아래 명령을 직접 실행:

```bash
# jq 방식 (권장)
jq -s '.[0].mcpServers * .[1].mcpServers | {mcpServers: .}' \
  .claude/settings.json \
  templates/mcp/supabase.json \
  > /tmp/merged.json && mv /tmp/merged.json .claude/settings.json
```

또는 `merge-example.sh` 스크립트 사용:

```bash
bash templates/mcp/merge-example.sh --preset supabase --dry-run   # 미리보기
bash templates/mcp/merge-example.sh --preset supabase              # 실제 병합
bash templates/mcp/merge-example.sh --preset vercel                # Vercel 병합
```

### 2단계 — 환경변수 설정

```bash
# .env.local (gitignore됨) 또는 셸 프로필에 추가
export SUPABASE_ACCESS_TOKEN="..."   # Supabase 대시보드 > Account > Access Tokens
export VERCEL_API_TOKEN="..."        # Vercel 대시보드 > Settings > Tokens
```

**절대 이 값을 templates/mcp/*.json에 직접 쓰지 말 것.**

### 3단계 — 전역 설정에 추가 (선택)

프로젝트마다 병합하는 대신 `~/.claude/settings.json`에 한 번만 추가:

```bash
bash templates/mcp/merge-example.sh --preset supabase --global
```

---

## 활성화 확인

Claude Code 세션 안에서:

```
/mcp
```

`supabase` 또는 `vercel` 항목이 `connected` 상태로 표시되면 정상이다.

---

## 금지 사항

| 금지 | 이유 |
|------|------|
| API 키를 JSON 파일에 하드코딩 | git 커밋 시 영구 노출 위험 |
| `.env` 파일 커밋 | 전역 보안 규칙 위반 |
| `cat .env` 실행 | 키값이 터미널에 노출됨 — `grep -c "KEY_NAME" .env`만 허용 |
| 실제 토큰을 채팅창에 붙여넣기 | 대화 로그에 영구 기록됨 |

---

## 참조 링크

- [Supabase MCP 공식 문서](https://supabase.com/docs/guides/getting-started/mcp)
- [Vercel MCP 공식 문서](https://vercel.com/docs/mcp)
- [MCP Authorization Spec (OAuth 2.1)](https://modelcontextprotocol.io/specification/2025-03-26/basic/authorization)
- [RFC 8707 — Resource Indicators for OAuth 2.0](https://datatracker.ietf.org/doc/html/rfc8707)
- [idea-factory sync-manifest.json](../../sync-manifest.json) — 이 파일들의 동기화 설정
