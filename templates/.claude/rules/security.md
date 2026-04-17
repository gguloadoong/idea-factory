# 시크릿 & 보안 규칙

## 절대 금지 (ANY 파일, ANY 커밋)

- API 키 / 토큰 / 비밀번호 하드코딩 금지
- `.env` 파일 커밋 금지 (`.gitignore`에 반드시 포함)
- 클라우드 자격증명(AWS, GCP, Vercel, Supabase 등) 커밋 금지
- 인증서·개인키(`.pem`, `.p12`, `.key`) 커밋 금지

## .env 파일 접근 규칙

- `cat .env` 금지 — 키값이 터미널·대화창에 노출됨
- 키 존재 여부 확인: `grep -c "KEY_NAME" .env` (값 노출 없이 개수만 반환)
- AI 에이전트가 `.env` 내용을 인용하거나 출력하는 것 금지

## 시크릿 패턴 감지 즉시 알림

다음 패턴이 코드·커밋·채팅에 등장하면 즉시 경고하고 작업 중단:

```
AKIA[0-9A-Z]{16}          # AWS Access Key
sk-[a-zA-Z0-9]{32,}       # OpenAI / Anthropic API Key
ghp_[a-zA-Z0-9]{36}       # GitHub Personal Access Token
xoxb-[0-9]+-[a-zA-Z0-9]+ # Slack Bot Token
AIza[0-9A-Za-z-_]{35}     # Google API Key
```

## 환경변수 관리

- 모든 시크릿은 환경변수로 주입: `process.env.SECRET_KEY`
- 로컬: `.env.local` (gitignore됨)
- 배포: Vercel / 플랫폼 환경변수 UI 또는 CLI (`vercel env add KEY production`)
- `.env.example`에는 키 이름만 기재, 값은 빈칸: `OPENAI_API_KEY=`

## 코드 보안 기본

- SQL/NoSQL 쿼리: 파라미터 바인딩 필수, 문자열 접합 금지
- XSS 방지: `innerHTML` 대신 `textContent`, React는 `dangerouslySetInnerHTML` 지양
- 비밀번호 저장: bcrypt 또는 argon2 (MD5/SHA1 금지)
- API 엔드포인트: 소유권 검증 필수 (본인 리소스만 접근 가능한지 확인)
- 쿠키: `SameSite=Strict`, `HttpOnly`, `Secure` 속성 설정
