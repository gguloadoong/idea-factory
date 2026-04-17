# 감사 로그 분석 가이드 (Audit Log Analysis Guide)

idea-factory v8 item 1.4 — `check-audit.sh`가 기록하는 JSONL 로그를
검색·분석하는 두 도구의 사용법과 운영 지침.

---

## JSONL 스키마

`check-audit.sh`가 `.claude/audit/YYYY-MM-DD.jsonl`에 기록하는 실제 필드:

| 필드 | 타입 | 설명 |
|---|---|---|
| `ts` | string | ISO-8601 UTC 타임스탬프 (예: `2026-04-17T09:30:00Z`) |
| `session` | string | Claude Code 세션 ID (`CLAUDE_SESSION_ID` 환경변수 값) |
| `matcher` | string | 항상 `"Bash"` (PreToolUse Bash 매처 고정값) |
| `tags` | string | 공백 구분 태그 목록 또는 빈 문자열. 가능한 값: `deploy` `redis-flush` `npm-install` `git-destructive` `rm-rf` |
| `cmd` | string | 실행된 Bash 명령어 (최대 2048자, 초과 시 `...[truncated]` 추가) |

**주의**: exit code 필드는 스키마에 없음. 명령 성공/실패 여부는 로그에서 확인 불가.

---

## 기본 사용법

### 1. 오늘 감사 로그 전체 보기
```bash
bash scripts/audit-grep.sh
```

### 2. 최근 2시간 내 이벤트 검색
```bash
bash scripts/audit-grep.sh --since 2h
```

### 3. 특정 태그(deploy)가 포함된 이벤트 필터
```bash
bash scripts/audit-grep.sh --all --tool deploy
```

### 4. cmd 필드에서 정규식 패턴 검색
```bash
bash scripts/audit-grep.sh --since 1d --grep "npm install"
```

### 5. 특정 세션의 모든 이벤트 (원시 JSONL)
```bash
bash scripts/audit-grep.sh --all --session <SESSION_ID> --json
```

### 6. 오늘 가장 빈번한 명령어 상위 10개
```bash
bash scripts/audit-grep.sh --top 10
```

### 7. 전체 기간 세션별 요약 (이벤트 수 + 첫/마지막 시각)
```bash
bash scripts/audit-grep.sh --all --summary
```

### 8. 특정 날짜 로그 분석 리포트
```bash
bash scripts/audit-grep.sh --date 2026-04-15 | python3 scripts/audit-analyze.py --all
```

---

## 분석 워크플로우

두 도구는 단계적으로 사용한다.

```
.claude/audit/YYYY-MM-DD.jsonl
         │
         ▼
  audit-grep.sh          ← 1단계: 원하는 이벤트 필터링
  (jq 기반 검색)
         │
         ▼
  audit-analyze.py       ← 2단계: 패턴 감지 및 리포트 생성
  (Python 표준 라이브러리)
```

### 전형적인 체인 예시

```bash
# 전체 로그에서 이상 패턴 감지 리포트 생성
python3 scripts/audit-analyze.py --all

# 최근 24시간만 분석
python3 scripts/audit-analyze.py --all --since 24h

# JSON 형태로 출력 (CI 파이프라인 연동용)
python3 scripts/audit-analyze.py --all --json

# rm-rf 이벤트만 추출 후 상세 확인
bash scripts/audit-grep.sh --all --tool rm-rf --json | jq '{ts,session,cmd}'
```

### `audit-analyze.py` 감지 패턴

| 패턴 | 감지 기준 | 비고 |
|---|---|---|
| 반복 명령 (repeated-failure) | 동일 cmd가 세션 내 ≥3회 등장 | exit code 없어 실패 직접 판별 불가 — 재시도로 간주 |
| 빈도 이상 (frequency-anomaly) | 세션 내 태그 빈도가 평균 대비 3σ 초과 | |
| 보안 민감 패턴 (suspicious-pattern) | `rm -rf`, `sudo`, `curl | bash`, `.env` 등 정규식 매칭 | 의도적 사용일 수도 있음 — 컨텍스트 확인 필수 |

---

## 보안 주의사항

감사 로그(`cmd` 필드)에는 다음이 포함될 수 있다:

- 환경변수 값이 인자로 전달된 명령어
- 파일 경로, 브랜치 이름, 임시 토큰
- git commit 메시지, SQL 쿼리

**공유 시 반드시 마스킹**:

```bash
# cmd 필드에서 민감 값 마스킹 후 공유
bash scripts/audit-grep.sh --all --json \
  | jq 'del(.cmd) + {cmd: "REDACTED"}' > safe-audit.jsonl
```

`.claude/audit/` 디렉터리는 `.gitignore`로 보호되어 있음 (`check-audit.sh`가 첫 실행 시 자동 생성).

---

## 운영 팁

### 용량 관리

감사 로그는 세션당 수백~수천 줄 기록될 수 있다. 월 1회 정도 정리를 권장.

```bash
# 30일 이전 로그 삭제
find .claude/audit/ -name "*.jsonl" -mtime +30 -delete

# 현재 로그 크기 확인
du -sh .claude/audit/
```

### 로테이션

자동 로테이션이 필요하면 cron 또는 logrotate 사용:

```
# crontab 예시: 매월 1일 오전 2시 90일 이전 로그 삭제
0 2 1 * * find /path/to/project/.claude/audit/ -name "*.jsonl" -mtime +90 -delete
```

### 백업

로그는 `.gitignore`로 커밋에서 제외되므로, 장기 보관이 필요하면 별도 백업 필요:

```bash
# 월별 아카이브
tar -czf audit-$(date +%Y-%m).tar.gz .claude/audit/*.jsonl
```

### 환경변수 오버라이드

`AUDIT_DIR` 환경변수로 로그 경로를 변경할 수 있다:

```bash
AUDIT_DIR=/var/log/claude-audit bash scripts/audit-grep.sh --all --summary
AUDIT_DIR=/var/log/claude-audit python3 scripts/audit-analyze.py --all
```
