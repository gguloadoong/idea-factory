# AI 회귀 방지

AI 에이전트가 반복 작업할 때 가장 흔히 발생하는 문제는 이미 삭제된 코드가 부활하거나,
이전 세션의 결정이 무시되는 것이다. 이 규칙은 그것을 막기 위한 것이다.

## 1. 좀비 파일 즉시 삭제

컴포넌트·함수·모듈을 삭제할 때는 **파일도 함께 삭제**한다.

- 파일이 남아 있으면 다음 AI 세션이 re-import함
- "나중에 쓸 수도 있으니 남겨둔다"는 이유로 파일 존재를 허용하지 않음
- 삭제 후 git commit — 히스토리에서 복구 가능

## 2. CONTRACT 패턴

기능 디렉터리마다 `*_CONTRACT.md`를 유지한다:

```markdown
# [기능명] CONTRACT

## 활성 컴포넌트
- ComponentA — [역할 설명]
- ComponentB — [역할 설명]

## 영구 삭제 목록 (재추가 금지)
- ~~OldComponent~~ — 삭제 이유: 성능 문제. 재추가 금지 이유: ComponentB가 대체함
```

세션 시작 시 기능 디렉터리를 건드리기 전에 해당 `*_CONTRACT.md`를 먼저 읽는다.

## 3. 아키텍처 테스트

삭제된 컴포넌트가 import되면 CI가 실패하도록 테스트를 작성한다:

```typescript
// tests/architecture.test.ts
test('삭제된 OldComponent가 import되지 않아야 함', () => {
  const files = getAllSourceFiles('./src');
  const forbidden = files.filter(f => f.includes('OldComponent'));
  expect(forbidden).toHaveLength(0);
});
```

## 4. Done = 실제 확인

"완료"의 정의:

- [ ] 실제 데이터로 수동 검증 (체크리스트 틱만으로는 완료 아님)
- [ ] 브라우저·터미널에서 직접 확인
- [ ] 엣지 케이스 (빈 값, 에러 상태) 확인

"코드가 맞아 보인다"는 완료가 아니다.

## 5. 독립 리뷰 — PR 전 필수

- 구현 컨텍스트와 **분리된** `code-reviewer` 에이전트에게 diff를 전달
- 같은 세션에서 자기 코드를 자기가 리뷰하는 것은 무효
- 리뷰어는 워크트리 격리(`isolation: "worktree"`)로 실행
- CRITICAL / HIGH 결함이 0개일 때만 PR 생성

## 결정 보존

- `decisions.md`에 이미 기록된 결정은 재논의하지 않음
- "왜 이렇게 했지?"라는 의문이 들면 파일을 쓰기 전에 `decisions.md`를 먼저 읽음
- 같은 접근이 2번 실패하면 근본 원인 분석, 3번 실패하면 전략 전환
