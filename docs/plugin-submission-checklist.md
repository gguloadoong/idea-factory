# 플러그인 마켓플레이스 제출 체크리스트

> idea-factory를 Claude Code 공식 마켓플레이스 및 커뮤니티 마켓플레이스에 제출하기 위한 준비 절차

---

## 1. 제출 전 준비 체크리스트

### plugin.json 유효성

- [ ] `name` 필드 존재 (유일한 필수 필드)
- [ ] `version` 시맨틱 버저닝 형식 준수 (`MAJOR.MINOR.PATCH`)
- [ ] `description` 한 문장, 영어 (마켓플레이스 목록 표시용)
- [ ] `author.name` 기재
- [ ] `license` 명시 (`"MIT"`)
- [ ] `keywords` 배열 5개 이상 (검색 최적화)
- [ ] `homepage` / `repository` URL 유효 확인
- [ ] 모든 경로 필드는 상대 경로 + `./` 시작 (`"./skills/"` 형식)
- [ ] JSON 문법 오류 없음 (`claude plugin validate` 로컬 실행)

### 구조 검증

- [ ] `.claude-plugin/plugin.json` 위치 정확 (`.claude-plugin/` 안에만 존재)
- [ ] `skills/` 디렉터리는 플러그인 루트에 위치 (`.claude-plugin/` 안 금지)
- [ ] `skills/start-company/SKILL.md` 존재 및 frontmatter 유효
- [ ] `README.md` 또는 `.claude-plugin/marketplace-readme.md` 존재

### 보안 선언 확인

- [ ] 하드코딩된 API 키 / 토큰 / 비밀번호 없음
- [ ] `.env` 파일이 `.gitignore`에 포함됨
- [ ] MCP 프리셋이 환경변수 참조 사용 (`${ENV_VAR}` 형식)
- [ ] `templates/settings.json`의 `permissions.deny` 리스트 유지 확인
- [ ] 시크릿 패턴 스캔: `grep -r "AKIA\|sk-\|ghp_\|xoxb-\|AIza" .`

### 테스트 통과

- [ ] `tests/` 하네스 불변성 테스트 통과
- [ ] `claude --plugin-dir ./` 로컬 로드 성공
- [ ] `/idea-factory:start-company` 스킬 정상 호출
- [ ] `/reload-plugins` 오류 없음

---

## 2. Anthropic 공식 마켓플레이스 제출

공식 문서(https://code.claude.com/docs/en/plugins) 기준:

### 제출 경로

공식 마켓플레이스 제출은 인앱 제출 폼을 통해 진행한다. 레포 전송(transfer)이나 PR 방식이 아님.

- **Claude.ai**: https://claude.ai/settings/plugins/submit
- **Console**: https://platform.claude.com/plugins/submit

### 제출 절차

1. 위 URL 중 하나에서 제출 폼 접근
2. 플러그인 GitHub 레포 URL 입력: `https://github.com/gguloadoong/idea-factory`
3. `.claude-plugin/plugin.json` 경로 확인
4. 마켓플레이스 표시명, 카테고리, 설명 입력
5. 보안 및 이용 약관 동의
6. 제출 후 Anthropic 검토 대기 (검토 기간 공개 안 됨)

> **참고**: 공식 CLI 설치 명령은 마켓플레이스 등록 후 확정됨.
> 예상 형식: `claude plugin install idea-factory@claude-plugins-official`

---

## 3. 커뮤니티 마켓플레이스 제출

### 3-1. hesreallyhim/awesome-claude-code

GitHub: https://github.com/hesreallyhim/awesome-claude-code

절차:
1. 레포 Fork
2. `README.md`의 Plugins 섹션에 항목 추가:
   ```markdown
   - [idea-factory](https://github.com/gguloadoong/idea-factory) — Virtual startup factory: one-line idea → working MVP via autonomous AI team
   ```
3. PR 제출 (제목 예: `Add idea-factory plugin`)
4. 메인테이너 리뷰 대기

### 3-2. ComposioHQ/awesome-claude-plugins

GitHub: https://github.com/ComposioHQ/awesome-claude-plugins

절차:
1. 레포 Fork
2. 카테고리(Development Tools / Productivity)에 항목 추가
3. PR 제출
4. CI 자동 검증 + 메인테이너 리뷰 대기

### 3-3. claudemarketplaces.com

URL: https://claudemarketplaces.com

절차:
1. 사이트에서 "Submit Plugin" 또는 유사 폼 접근
2. 플러그인 정보 (이름, 설명, GitHub URL, 키워드) 입력
3. 제출 후 수동 검토 대기

---

## 4. 거부 시 대응 절차

### 공식 마켓플레이스 거부

1. **피드백 확인**: 거부 이메일 또는 인앱 알림에서 거부 사유 파악
2. **항목별 수정**:
   - 보안 문제 → `templates/settings.json` 또는 MCP 프리셋 수정
   - 스키마 오류 → `.claude-plugin/plugin.json` 수정 후 `claude plugin validate` 재실행
   - 문서 미흡 → `.claude-plugin/marketplace-readme.md` 보완
3. **버전 범프**: `plugin.json`의 `version` 패치 버전 올림
4. **재제출**: 동일 폼에서 재제출 또는 담당자 회신 이메일 통해 재검토 요청

### 커뮤니티 PR 거부

1. PR 코멘트에서 메인테이너 피드백 확인
2. 요청된 형식 변경 또는 설명 보완
3. 같은 브랜치에서 추가 커밋 후 PR 업데이트 (새 PR 불필요)

---

## 5. 제출 후 관리

- [ ] 마켓플레이스 등록 URL을 `README.md`의 Install 섹션에 추가
- [ ] `CHANGELOG.md`에 마켓플레이스 등록 날짜 기록
- [ ] 버전 업데이트 시 `plugin.json`의 `version` 필드 동기화
- [ ] 사용자 이슈 모니터링 (GitHub Issues)
