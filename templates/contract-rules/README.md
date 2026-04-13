# contract-rules — 기계적으로 강제되는 코드 제약

## 개념

`CONTRACT.md`의 자연어 FAQ는 **"왜"**를 설명한다. 이 디렉터리의 규칙 파일은 **"무엇을"** 차단하는지를 코드로 정의한다.

에이전트가 CONTRACT.md를 읽지 않거나 무시해도 `scripts/check-contract.sh`가 위반을 탐지한다.

## 사용법

```bash
# 기본 모드 — 위반 경고 출력, exit 0
bash scripts/check-contract.sh

# 규칙 파일 지정
bash scripts/check-contract.sh --rules templates/contract-rules/my-rules.yml

# 검사 경로 지정
bash scripts/check-contract.sh --path src/

# CI 모드 — 위반 시 exit 1
bash scripts/check-contract.sh --strict
```

## 규칙 파일 형식

```yaml
rules:
  - id: rule-id              # 고유 식별자 (slug)
    description: "설명"      # 사람이 읽는 설명
    pattern: "regex"         # grep -E 패턴
    files:                   # 검사할 파일 glob 목록
      - "src/**/*.ts"
    action: warn             # warn (기본) | error
    contract_ref: "CONTRACT.md #anchor"  # 참조 문서
```

## ast-grep 지원

`ast-grep`이 설치된 환경에서는 regex 대신 구조적 AST 패턴 매칭을 사용할 수 있다. 현재 버전은 regex fallback으로 동작하며, ast-grep 통합은 향후 확장 예정이다.

## pre-commit 통합

`.git/hooks/pre-commit` 또는 lefthook/husky에 아래를 추가:

```bash
bash scripts/check-contract.sh --strict
```
