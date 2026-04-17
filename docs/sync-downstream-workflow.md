# Downstream Sync Workflow 가이드

`.github/workflows/sync-downstream.yml` — idea-factory 템플릿 변경을 `downstream-registry.json`에 등록된 다운스트림 프로젝트로 전파하는 GitHub Actions 워크플로우.

**핵심 설계**: `workflow_dispatch` 전용 (수동 트리거) — `push` 이벤트에 자동 반응하지 않는다. 10개 레포에 의도치 않은 PR이 쏟아지는 사고를 구조적으로 막기 위함.

---

## 언제 실행하나

`templates/` 또는 `scripts/` 하위 파일을 main에 머지한 뒤, 다운스트림에 전파할 준비가 됐을 때 대표가 수동으로 실행한다.

권장 흐름:

1. **Dry-run**: `mode = check` 으로 먼저 drift 리포트만 생성 → 어떤 레포·어떤 파일에 변경이 가는지 확인
2. **Apply**: 예상대로면 `mode = apply` 로 재실행 → 각 다운스트림 레포에 PR 자동 생성
3. **리뷰 + 머지**: 다운스트림 레포 오너가 PR을 리뷰·머지 (자동 머지 아님)

---

## 최초 설정 (1회)

### 1. Personal Access Token 발급

다운스트림 10개 레포 모두에 write 권한이 있어야 한다. GitHub의 기본 `GITHUB_TOKEN`은 현재 레포 scope라 쓸 수 없다.

1. https://github.com/settings/tokens → **Generate new token (classic)**
2. 권한: `repo` (Full control of private repositories) — 또는 fine-grained PAT에서 각 다운스트림 레포 Contents/Pull Requests `write` 선택
3. 만료 기한은 6~12개월 권장 (만료 전 갱신 알림 설정)
4. 토큰 값 복사 (다시 볼 수 없음)

### 2. 저장소 시크릿 등록

1. `gguloadoong/idea-factory` → **Settings** → **Secrets and variables** → **Actions**
2. **New repository secret**
3. Name: `SYNC_PAT`
4. Secret: 방금 복사한 PAT
5. **Add secret**

**주의**: 이 시크릿은 `.github/workflows/*.yml` 실행 시에만 주입되고, 로그·Issue·PR에 노출되지 않는다. 절대 `echo`로 출력하지 말 것.

---

## 실행 방법

### GitHub UI

1. https://github.com/gguloadoong/idea-factory/actions/workflows/sync-downstream.yml
2. **Run workflow** 버튼
3. 입력값 선택:
   - **mode**: `check` (드라이런, 기본) 또는 `apply` (PR 생성)
   - **repo**: 특정 레포만 대상 (예: `signalplay`) 또는 비워두면 전체
   - **verbose**: 파일 단위 diff를 로그에 출력할지
4. **Run workflow**

### gh CLI

```bash
# Dry-run 전체
gh workflow run sync-downstream.yml \
  --repo gguloadoong/idea-factory \
  -f mode=check

# 특정 레포만 apply
gh workflow run sync-downstream.yml \
  --repo gguloadoong/idea-factory \
  -f mode=apply \
  -f repo=signalplay \
  -f verbose=true

# 실행 결과 확인
gh run list --workflow=sync-downstream.yml --repo gguloadoong/idea-factory --limit 5
```

---

## 결과 확인

- **Actions 탭**: 실행 중인 / 완료된 job 로그
- **Summary**: 각 run 하단의 "Sync Downstream Summary" 블록
- **다운스트림 PR**: `apply` 모드였다면 각 다운스트림 레포 Pull Requests 탭에 새 PR
- **drift 없는 레포**: 로그에 "no drift" 표시, PR 생성 안 됨

---

## 안전 장치

- **workflow_dispatch only**: `push` / `schedule` 트리거 없음 → 의도치 않은 실행 불가
- **check 모드 기본값**: 드라이런으로 먼저 확인하는 습관 유도
- **sync-downstream.sh exit 0 invariant**: 워크플로우가 에러로 터져도 레포 상태 망가뜨리지 않음
- **PAT scope 격리**: `SYNC_PAT`은 이 워크플로우에서만 주입, 다른 job은 접근 불가
- **10개 레포 한꺼번에 실행 가능**: `repo` 인자를 비우면 전체 실행 — 실수 위험. **첫 실행은 반드시 `repo`에 1개 레포 지정해서 smoke test** 권장

---

## 문제 해결

### "SYNC_PAT secret is not set"
→ 위 "저장소 시크릿 등록" 단계 수행. 저장소 owner만 설정 가능.

### "gh not authenticated"
→ 워크플로우 내부에서 gh CLI가 `SYNC_PAT`을 인식하지 못함. `GH_TOKEN` 또는 `GITHUB_TOKEN` env에 PAT이 들어갔는지 워크플로우 YAML 확인.

### drift가 예상과 다르다
→ `sync-manifest.json`의 분류 확인:
- `managed`: 1:1 동기화 대상 (drift = 덮어쓰기 대상)
- `computed`: 스크립트로 생성 (`scripts/merge-settings.sh` 등) — 원본 edit 아님
- `customized`: 다운스트림 자유 편집 (drift 무시)

### PR이 안 만들어진다
→ 대부분 토큰 권한 문제. PAT가 **해당** 다운스트림 레포 `repo` scope를 포함하는지 확인. Fine-grained PAT은 레포별 접근 명시 필요.

---

## 관련 파일

- `scripts/sync-downstream.sh` — 실행 엔트리 포인트 (bash)
- `scripts/sync-lib.py` — drift 감지 + PR 생성 로직 (Python)
- `sync-manifest.json` — 파일 분류 (managed/computed/customized)
- `downstream-registry.json` — 다운스트림 레포 목록 + 타입 + 스캐폴드 날짜

## 향후 계획

- **v2 자동 트리거**: 템플릿 변경 PR 머지 시 자동 `check` 모드 실행 (로그만, PR 생성 없음) — 조기 drift 감지
- **Slack/Discord 알림**: 워크플로우 결과 요약을 대표 채널로 푸시
- **일괄 머지**: 다운스트림 PR들을 한 번에 승인 가능한 메타 대시보드
