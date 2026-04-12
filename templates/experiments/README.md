# Experiments

This directory tracks parameter tuning experiments. Each file records a single parameter change: the hypothesis, backtest result, and final decision.

## Purpose

When work = parameter delta (not file diff), this directory is the audit trail. It answers:
- What was the parameter before?
- Why was it changed?
- Did the backtest support the change?
- Was it kept or reverted?

Without this trail, parameter drift accumulates silently. Systems degrade and no one knows why.

## File Naming

```
YYYY-MM-DD-param-name.md
```

Examples:
```
2026-04-13-rsi-threshold.md
2026-04-15-ema-period.md
2026-04-20-stop-loss-pct.md
2026-05-01-learning-rate.md
```

One file per tuning session. One session = one parameter change.

## File Format

```markdown
# <parameter-name> — <YYYY-MM-DD>

## Parameter
- **Name:** `<parameter_name>`
- **File:** `<path/to/config/file>`
- **Before:** `<old-value>`
- **After:** `<new-value>`

## Hypothesis
<One sentence: why do you expect this change to improve the target metric?>

## Target Metric
- **Metric:** <e.g., Sharpe ratio, win rate, max drawdown, RMSE>
- **Keep threshold:** <e.g., Sharpe improves by ≥ 0.05>
- **Revert threshold:** <e.g., drawdown worsens by > 2%>

## Backtest
- **Period:** <YYYY-MM-DD to YYYY-MM-DD>
- **Dataset:** <e.g., BTC/USDT 1h, S&P500 daily>
- **Before:** <metric value>
- **After:** <metric value>
- **Delta:** <+/- value>
- **Threshold met:** yes / no

## Observations
<Any anomalies, caveats, or context about the backtest window>

## Decision
**KEEP** / **REVERT**

**Reason:** <one sentence>

## Commit
`<git commit hash>`
```

## Workflow

1. Create the experiment file before changing the parameter.
2. Fill in Parameter, Hypothesis, and Target Metric sections first.
3. Run the backtest.
4. Fill in Backtest and Observations sections.
5. Record Decision.
6. Copy the ADR summary into `decisions.md` (see tuning ADR template).
7. Commit the parameter change with the experiment file and decisions.md update together.

## Protocol Reference

Full protocol: [`templates/workflows/tuning-session.md`](../workflows/tuning-session.md)

Gate script: [`scripts/tuning-gate.sh`](../../scripts/tuning-gate.sh)
