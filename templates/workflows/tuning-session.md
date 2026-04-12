# Tuning Session Protocol

A tuning session is how this project tracks parameter changes in trading bots, ML models, and pricing engines. Unlike code changes where work = file diff, parameter tuning work = parameter delta with measurable outcome.

## When to Use

Use this protocol whenever you change a numeric parameter that controls system behavior:

- Trading signal thresholds (e.g., RSI cutoff, stop-loss %, position size)
- ML model hyperparameters (e.g., learning rate, batch size, regularization weight)
- Pricing engine coefficients (e.g., spread multiplier, inventory skew factor)
- Risk limits (e.g., max drawdown %, VaR threshold)
- Time-series window sizes (e.g., EMA period, lookback days)

If your change is "I updated the RSI threshold from 30 to 28" — this protocol applies.
If your change is "I refactored the indicator calculation function" — standard code review applies.

## Protocol Steps

### 1. Document Current Value + Rationale

Before touching any parameter file, record:
- What the current value is
- Why it was set to that value (or "unknown" if inherited)
- What problem you are trying to solve

This goes in your experiment file: `.omc/experiments/YYYY-MM-DD-param-name.md`

### 2. Define Target Metric + Threshold

State what success looks like before running any backtest:
- Which metric you are optimizing (Sharpe ratio, win rate, max drawdown, RMSE, etc.)
- What threshold constitutes an improvement worth keeping
- What threshold constitutes a regression that should block the change

Example: "Sharpe ratio must improve by ≥ 0.05, drawdown must not worsen by > 2%"

Defining this before the backtest prevents post-hoc rationalization.

### 3. Run Backtest

Run your backtest or evaluation against the same dataset used for the current baseline.

Requirements:
- Same time range as baseline
- Same market conditions (do not cherry-pick a favorable window)
- Record full output, not just the headline metric
- Note any anomalies (e.g., unusually low volatility in the test window)

### 4. Record Result in decisions.md

Add an ADR entry to `decisions.md` (see template below). The entry must include:
- Before and after values
- Metric outcome (pass/fail against your threshold)
- Decision: keep or revert
- Date

### 5. One Parameter Per Commit

Each commit must change exactly one parameter. This is enforced by `scripts/tuning-gate.sh`.

Rationale: when you change RSI threshold AND EMA period in the same commit and performance improves, you do not know which change caused it. You cannot safely revert one without the other. Single-parameter commits make causality traceable.

## Anti-Patterns

**Changing multiple parameters at once**
You lose the ability to attribute outcomes. If performance degrades, you cannot isolate the cause. Revert costs you multiple experiments.

**No backtest before committing**
Parameter changes without evidence are configuration drift. They accumulate silently and degrade system performance over weeks.

**No baseline recorded**
If you do not record the before value, you cannot revert precisely. "It was around 30" is not a baseline.

**Optimizing on the test window**
Running many parameter variants on the same window and keeping the best one is data snooping. The apparent improvement will not generalize. Use a fixed evaluation window; hold out a validation window for final confirmation.

**Copying parameters from another system without validation**
Parameters are context-dependent. A threshold that works for BTC/USD does not necessarily transfer to ETH/USD or a different timeframe.

## Tuning ADR Template

Copy this block into `decisions.md` for each tuning session:

```markdown
## [PARAM] <parameter-name> — <YYYY-MM-DD>

**File:** `<path/to/config/file>`
**Before:** `<old-value>`
**After:** `<new-value>`

### Hypothesis
<One sentence: why do you expect this change to improve the metric?>

### Target Metric
- Metric: <e.g., Sharpe ratio, win rate, RMSE>
- Threshold for keep: <e.g., Sharpe ≥ 0.05 improvement>
- Threshold for revert: <e.g., drawdown worsens > 2%>

### Backtest Result
- Period: <YYYY-MM-DD to YYYY-MM-DD>
- Before: <metric value>
- After: <metric value>
- Delta: <+/- value>
- Threshold met: yes / no

### Decision
**KEEP** / **REVERT**

Reason: <one sentence>

### Experiment File
`.omc/experiments/YYYY-MM-DD-<parameter-name>.md`
```

## Related

- Experiment files: `.omc/experiments/` (see README there)
- Gate script: `scripts/tuning-gate.sh`
- Field report: `docs/field-reports/` (post-mortems on parameter drift incidents)
