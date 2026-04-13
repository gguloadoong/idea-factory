# Tuning Gate Guide — numeric-tuning preset 활용법

## 개요

`templates/gate-presets/numeric-tuning.yml` 은 파라미터 튜닝 PR 전용 2-reviewer gate preset.
4-reviewer full gate 는 숫자 변경에 overkill — architect (구조/불변) + code-reviewer (품질/backtest 대조) 2명으로 충분.

## 빠른 시작

```bash
# preset 지정하여 gate 실행
GATE_RULES=templates/gate-presets/numeric-tuning.yml bash scripts/run-gate.sh

# dry-run 으로 리뷰어 선택 시뮬레이션
GATE_RULES=templates/gate-presets/numeric-tuning.yml bash scripts/run-gate.sh --dry-run

# 특정 파일 목록으로 테스트
GATE_FILES="config/model.params.json" \
  GATE_RULES=templates/gate-presets/numeric-tuning.yml \
  bash scripts/run-gate.sh --dry-run
```

## tuning-session.md 프로토콜과 연동

`templates/workflows/tuning-session.md` 의 각 단계에 gate 를 통합:

1. **파라미터 변경 커밋 전** — tuning-gate.sh 로 1-param-per-commit 규칙 확인
2. **PR 열기 전** — `run-gate.sh` 로 리뷰어 세트 확인 (numeric-tuning preset 사용)
3. **리뷰어에게 backtest 결과 제공** — PR 본문에 아래 형식으로 첨부

```markdown
## Backtest Summary
- parameter: `rsi_threshold` 30 → 28
- period: 2024-01-01 ~ 2024-12-31
- sharpe: 1.42 → 1.51 (+0.09)
- max_drawdown: -8.3% → -7.9%
- decisions: [decisions.md](./decisions.md)
```

## 파일 패턴별 리뷰어 선택

| 파일 패턴 | 리뷰어 | 이유 |
|-----------|--------|------|
| `*config*.json`, `*params*.json` | architect | 구조/불변 체크 |
| `*constants*.js`, `*constants*.ts` | architect | 구조/불변 체크 |
| `*threshold*`, `*weight*`, `*factor*`, `*ratio*` | architect | 수치 파라미터 |
| `decisions.md`, `DECISIONS.md` | 없음 | ADR 기록, 리뷰 불필요 |
| `*.md` | 없음 | 문서 변경, 리뷰 불필요 |
| 그 외 | architect + code-reviewer | 튜닝 외 코드 변경 |

## 한 파라미터 per 커밋 규칙과의 통합

tuning-gate.sh 가 먼저 1-param-per-commit 을 검사하고, run-gate.sh 가 리뷰어를 선택한다.
두 gate 를 함께 사용하는 권장 순서:

```bash
# 1. 튜닝 프로토콜 준수 확인
bash scripts/tuning-gate.sh

# 2. 리뷰어 선택 (numeric-tuning preset)
GATE_RULES=templates/gate-presets/numeric-tuning.yml bash scripts/run-gate.sh
```

PR 훅이나 CI 에 통합할 때는 두 명령을 순서대로 실행. 둘 다 advisory-only (exit 0 보장).

## GATE_RULES 환경변수로 preset 전환

프로젝트마다 다른 preset 을 사용하려면:

```bash
# 기본 gate (전체 규칙)
bash scripts/run-gate.sh

# 튜닝 전용 preset (2-reviewer)
GATE_RULES=templates/gate-presets/numeric-tuning.yml bash scripts/run-gate.sh

# 프로젝트별 커스텀 preset
GATE_RULES=.gate-rules/my-project.yml bash scripts/run-gate.sh
```

`gate-rules.yml` 을 직접 수정하는 대신 preset 파일을 `GATE_RULES` 로 지정하면
기존 프로젝트 규칙을 건드리지 않고 튜닝 세션에서만 2-reviewer gate 를 사용할 수 있다.
