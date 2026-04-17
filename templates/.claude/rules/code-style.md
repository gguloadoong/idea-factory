# 코드 스타일

## 공통 원칙

- 함수 하나 = 책임 하나 (단일 책임 원칙)
- 함수 50줄 이내 — 초과 시 분리
- 매직 넘버 금지 → 상수로 이름 부여
- `any` 타입 금지 (TypeScript)
- 빈 `catch` 블록 금지 — 반드시 에러 처리 또는 로그

## TypeScript / JavaScript

```typescript
// 좋음: 명시적 타입, 에러 처리
async function fetchUser(id: string): Promise<User> {
  const res = await fetch(`/api/users/${id}`);
  if (!res.ok) throw new Error(`fetchUser failed: ${res.status}`);
  return res.json();
}

// 나쁨: any, 에러 무시
async function fetchUser(id: any): Promise<any> {
  const res = await fetch(`/api/users/${id}`);
  return res.json(); // 에러 상태 무시
}
```

- 비동기 함수: `async/await` 사용, `.then()` 체이닝 최소화
- 모든 비동기 호출에 타임아웃 설정 (무한 대기 방지)
- import: 상대 경로보다 절대 경로 (`@/`) 우선

## Python

```python
# 좋음: 타입 힌트, 명확한 예외
def fetch_user(user_id: str) -> dict:
    response = requests.get(f"/api/users/{user_id}", timeout=10)
    response.raise_for_status()
    return response.json()

# 나쁨: 타입 없음, 광범위한 except
def fetch_user(id):
    try:
        return requests.get(f"/api/users/{id}").json()
    except:
        pass
```

- 타입 힌트 필수 (`def func(x: int) -> str:`)
- `except Exception` 최소화 → 구체적 예외 명시
- f-string 사용 (`.format()` 대신)

## Shell 스크립트

```bash
#!/usr/bin/env bash
set -euo pipefail  # 필수: 에러 즉시 중단, 미정의 변수 오류

readonly CONFIG_FILE="config.json"  # 상수는 readonly

main() {
  echo "시작..."
}

main "$@"
```

- `set -euo pipefail` 항상 첫 줄에
- 변수는 항상 따옴표로 감쌈: `"$VAR"`
- 함수로 구조화, `main()` 진입점 명시

## YAML

- 들여쓰기: 스페이스 2칸 (탭 금지)
- 문자열: 특수문자 포함 시 따옴표 사용
- 시크릿 값은 환경변수 참조: `${{ secrets.KEY }}`
- 긴 파일은 주석으로 섹션 구분

## 에러 핸들링 원칙

1. 에러는 호출 스택 위로 전파하거나 명확히 로그
2. 사용자에게 보이는 에러 메시지는 한국어, 친절하게
3. 내부 로그는 영어, 구체적으로 (에러 코드, 컨텍스트 포함)
4. 재시도 가능한 에러와 불가능한 에러 구분
