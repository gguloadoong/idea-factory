# Research Report: trading-signal-bot Harness & DX Deep-Dive (architect)

**Date**: 2026-04-11
**Agent**: `oh-my-claudecode:architect` (Opus, read-only)
**Investigator context**: Session investigating what idea-factory v7.1 can contribute to trading-signal-bot DX, with focus on harness engineering, documentation hygiene, context degradation, and vibe-coding anti-patterns.
**Subject**: https://github.com/gguloadoong/trading-signal-bot (local path `/Users/bong/trading-signal-bot`)
**Output**: verbatim agent report, preserved for reference. Synthesis lives in `docs/field-reports/2026-04-11-tsb-contribution-plan.md`.

---

# Harness & DX Deep-Dive: idea-factory → trading-signal-bot

## TL;DR

- **trading-signal-bot is a parameter-tuning codebase masquerading as an app.** `_signal-engine.js` is 1116 lines of hand-tuned magic numbers (`MOMENTUM_ENTRY_PCT: 3.0`, `SR_PROXIMITY_PCT: 1.5`, `SHARP_DROP_PCT: -3`), and the continuous-learning plan will make this 5x worse. Its DX risk profile is fundamentally different from idea-factory's target (app scaffolding).
- **idea-factory v7.1 transplants badly at the runtime-safety layer.** `bypassPermissions + narrow deny-list` is wrong for a live-money bot where a bad `vercel env add` or an accidental `npm install <malicious>` has real cost. It needs an exit-0 audit-log hook (which idea-factory shelved as future work) — that gap is the single biggest idea-factory-v8 ask.
- **Fresh Context Isolation + two-pass defect-first review is the highest-leverage pattern to adopt**, specifically for protecting `DNA` parameter changes — and the 4-reviewer gate is overkill. A 2-reviewer gate (architect + backtest-qa) scaled to single-file diffs is right.
- **CONTRACT.md zombie-prevention maps perfectly** to trading-signal-bot's biggest risk: an agent reading `analysis/dna-v2-training.json` and silently re-adding RSI/MACD features to the DNA model, destroying the 3-layer purity defense documented in the continuous-learning plan.
- **Missing from idea-factory entirely**: a pattern for "numerical tuning sessions" where the work is *parameter deltas, not file diffs*. This is where trading-signal-bot DX most needs help and idea-factory v7.1 has nothing. See section E.

---

## A. Harness Engineering

### A.1 Risks in current signal engine

Read-grounded observations from the actual code:

- **`/Users/bong/trading-signal-bot/api/_signal-engine.js`** is 1116 lines, 5 models as plain object literals (DNA at `:159`, SENSE at `:416`, QUANT at `:589`, SHARK at `:749`), consensus aggregation at `:876-1002`. There is **no ensemble weight** — consensus is a simple model count (`consensusCount: count`). That means every "weight tuning" session an agent runs is actually a *threshold tuning* session on `score < 40` gates.
- **`api/_composite-scorer.js:12`** defines `WEIGHT` but that's for a different (TA/Flow/Sentiment) layer, not the 5-model ensemble. An agent confused between the two will "tune weights" in the wrong file and think it's done.
- **`api/_ta-core.js`** is 589 lines copied verbatim from market-dashboard-v5 (README line 15: "마켓레이더v5의 taCalculator.js를 복사한"). This is a **zombie-component factory**: every time Claude "helpfully" refactors a TA indicator, it diverges from the upstream copy with no mechanism to detect drift.
- **`api/_signal-engine.js:164-170`** has a comment *already warning future agents*: "⚠️ 현재는 하드코딩. 자동 학습 파이프라인은 Phase 2 예정." This is an *informal* contract. An agent aggressively "completing" this TODO without checking `/Users/bong/trading-signal-bot/.omc/plans/continuous-learning-architecture.md` (the 3-layer DNA purity defense) will silently violate the purity invariant.
- **The long-running-agent risk surface** is not "refactor this file" — it's **"tune this parameter and see if backtest improves"** loops. That is a *reward-hacked session* waiting to happen: the agent will edit `MOMENTUM_ENTRY_PCT`, run mental backtest, claim improvement, move on. No real evaluation pass occurs.

### A.2 Applicable patterns (with adapted form)

| Pattern | HARNESS-GUIDE section | Adapted form for trading-signal-bot |
|---|---|---|
| **Fresh Context Isolation (worktrees)** | "Design Decision: Fresh Context Isolation" | Tuning agent proposes parameter deltas as a JSON diff on a branch. A separate reviewer worktree runs a backtest harness (new: `scripts/backtest-against-signal-log.js`) with *only* the diff and Redis `signal:log` history — no access to tuning session reasoning. |
| **Two-Pass defect hunt → score** | "Design Decision: Two-Pass Evaluation" | Pass 1 (adversarial): "You are a quant reviewer. Find every reason this parameter change will overfit or break production." Pass 2: score only after defects enumerated. Critical for numeric changes where "looks fine" means nothing. |
| **Protected Files + run-architect.sh** | "Design Decision: Protected Files" | `.protected-files` should contain `api/_signal-engine.js`, `api/_ta-core.js`, `api/_composite-scorer.js`, `analysis/dna-v2-training.json`, and (once created) `api/dna-engine/**`. Architect review with commit-hash freshness is *especially* important here because parameter diffs look trivial. |
| **Quality Ratchet** | "Design Decision: Quality Ratchet" | Adapted metrics: `signal:log` 30-day winrate baseline, false-positive rate per model, consensus count distribution, zero-consensus days count. Ratchet rule: "30d winrate can't drop more than 5% absolute between commits touching `_signal-engine.js`." |
| **CONTRACT.md FAQ** | v7 changelog | Mandatory. See B.2. |
| **Phase handoff docs** | "Design Decision: Phase Handoff Documents" | Doesn't map 1:1 (no phases), but **tuning-experiment handoffs** do — see C.3. |
| **Fix-loop 3-attempt circuit breaker** | "CLAUDE.md 80-Line Limit" row in README | Essential. Tuning loops are the #1 place where "same parameter change 5 times in a row, nothing works" happens. |

### A.3 Runtime safety verdict — v7.1 is not enough for a live-money bot

**Verdict: INADEQUATE, but fixable.** The v7.1 deny-list (`Bash(rm -rf /)`, `Bash(sudo *)`, `Read(.env*)`, etc.) is the right *floor*, but it has material gaps for a bot where bad commands cost real money:

- `vercel --prod` is allowed. An agent that "helpfully" deploys after a tuning session can ship broken signals to a live Discord channel within 15 minutes (the cron interval). README line 63 *explicitly* reserves this for human approval ("배포는 대표 명시적 승인 후에만"), but that's documentation, not enforcement.
- `vercel env add` is allowed. An agent that decides to "fix" a missing env var can overwrite production secrets.
- `npm install <anything>` is allowed. Edge runtime + supply chain = real risk.
- No audit trail. If something breaks after a long autopilot session, there's no log of which commands the agent actually ran.

**Recommendation**: trading-signal-bot needs the **exit-0 logging hook** that HARNESS-GUIDE.md line 200 explicitly marks as "out of scope for v7.1". Concrete form:

1. PreToolUse Bash hook that *never halts* (exit 0), writes every command + timestamp + session id to `.omc/audit/YYYY-MM-DD.jsonl`.
2. Pattern-match warnings for `vercel --prod`, `vercel env`, `npm install`, `redis-cli FLUSHDB`, anything touching `signal:positions` — logged with a `CAREFUL` tag, not blocked.
3. Post-session, a separate reviewer agent reads the audit log and flags suspicious sequences.

Deny-list additions specifically for this project: `Bash(vercel --prod*)`, `Bash(vercel env rm*)`, `Bash(redis-cli FLUSHDB*)`, `Bash(redis-cli FLUSHALL*)`.

### A.4 Reviewer gate sizing — 4 is overkill; 2 is right

The 4-reviewer gate is designed for "Phase 1 → Phase 2 → Phase 3" app scaffolding with UI + business logic + security. trading-signal-bot changes are almost always:
- A parameter tweak in `_signal-engine.js`
- A new TA indicator in `_ta-core.js`
- A new cron handler

There's no UI, so `qa-tester` (Playwright) contributes zero. `critic` (essence drift) and `architect` largely overlap for single-file numeric changes.

**Proposed 2-reviewer gate for trading-signal-bot:**

1. **architect** (worktree, opus): structural review of the diff + invariant check against CLAUDE.md + CONTRACT.md
2. **backtest-qa** (worktree, sonnet): runs the backtest harness against `signal:log` history, reports 30d winrate delta, false-positive change, consensus distribution change — defect-first framing

Escalate to 4-reviewer only for: any change touching `api/dna-engine/**`, any change touching ensemble weighting when that lands, any change to `_composite-scorer.js`'s `WEIGHT` constant.

---

## B. Documentation Hygiene

### B.1 Proposed CLAUDE.md skeleton (~50 lines)

```markdown
# trading-signal-bot — Claude Instructions

## What this is
5-model signal engine (DNA/WALL ST/SENSE/QUANT/SHARK) on Vercel Edge, 15-min cron,
Discord alerts. Production. Real money decisions depend on this.

## Invariants — NEVER silently change
1. DNA model is purity-locked. It must NOT read `taCache`, `fundingData`, or
   anything from `_ta-core.js` / `_composite-scorer.js`. See
   `.omc/plans/continuous-learning-architecture.md` "DNA 순수성 3-Layer Defense".
2. `api/_ta-core.js` is a VERBATIM copy of market-dashboard-v5 `taCalculator.js`.
   Do not refactor. Drift from upstream is a bug.
3. `_signal-engine.js` consensus is COUNT-based, not weighted. Do not introduce
   ensemble weights without updating `CONTRACT.md` and the continuous-learning plan.
4. Parameter changes > ±10% require backtest evidence + CEO approval.
5. Production Redis (`signal:positions`, `signal:log`) is live. Never FLUSHDB.

## Session start checklist
1. Read `.omc/plans/continuous-learning-architecture.md`
2. Read `CONTRACT.md` FAQ (why things were removed)
3. Read `decisions.md` last 5 entries
4. If touching `_signal-engine.js`: read `.protected-files` protocol first

## What you need CEO approval for
- `vercel --prod`
- `vercel env add/rm` on production
- Any change to `_signal-engine.js` threshold > ±10%
- Any new model or ensemble weighting
- Any change to `api/dna-engine/**` (once created)

## Fix-loop circuit breaker
Same failure 3 times = STOP. Do not keep tuning parameters hoping it works.
Escalate to CEO with the 3 failed attempts logged.

## Tuning session protocol
When tuning numeric parameters:
1. State current value + reasoning + target metric BEFORE changing
2. Change ONE parameter at a time
3. Run backtest script (scripts/backtest.js) — not mental backtest
4. If no improvement after 3 attempts, stop
5. Commit each attempt separately so git log shows the search path
```

That's ~50 lines, under the 80-line limit, preserves the invariants the code already depends on.

### B.2 Zombie component risks (concrete list)

These are real cases in the current codebase where "removed for a reason" knowledge lives only in comments or commits:

1. **RSI/MACD/ATR in DNA features.** The continuous-learning plan documents this as a *hard* violation (3-layer defense), yet `analysis/dna-v2-training.json` contains those features and was used for the initial tuning. An agent told "improve DNA" will find this file and re-add them.
2. **Trailing stop in DNA.** `_signal-engine.js:157` explicitly comments: "트레일링 스톱은 WALL ST(Chandelier Exit)에 위임 (아키텍트 피드백 반영)". This is a zombie waiting to happen — an agent reading only DNA's code will "helpfully" add exit logic back.
3. **`score < 25` → `score < 40` threshold bump** at `_signal-engine.js:213` — noted as "MAJOR-3". A future agent optimizing for "more signals" will revert this without knowing why.
4. **`SR_PROXIMITY_PCT: 3 → 1.5`** at `_signal-engine.js:419` — noted as "MAJOR-6: 3→1.5 (진짜 근접만)". Same risk.
5. **`SHARP_DROP_PCT: -5 → -3`** at `_signal-engine.js:592` — noted as "Bug3: -5→-3 snap fallback 완화". Same risk.
6. **Python `models/` folder.** README: "건드리지 말 것" (do not touch). An agent "cleaning up dead code" will delete it, losing reference.
7. **`_ta-core.js` as a copy.** Any "improvement" is a zombie because the source of truth is elsewhere.

**CONTRACT.md minimum FAQ entries** (one-line each):
- Q: Why is DNA not allowed to read RSI/MACD? A: 3-layer purity defense in continuous-learning plan. Breaking this invalidates all DNA training.
- Q: Why does DNA have no trailing stop? A: Exits delegated to WALL ST (Chandelier) per architect feedback. Don't duplicate.
- Q: Why is the buy threshold 40 not 25? A: MAJOR-3 noise reduction. Consensus aggregation makes individual model score less important.
- Q: Why is SR_PROXIMITY_PCT 1.5? A: MAJOR-6 tightened to "actually near" only.
- Q: Why is SHARP_DROP_PCT -3 not -5? A: Bug3 snap fallback relaxation.
- Q: Why is `_ta-core.js` a copy instead of an import? A: Vercel Edge has no market-dashboard-v5 dependency. Upstream is source of truth — `taCalculator.js` in that repo.
- Q: Why no ensemble weights? A: Count-based consensus is intentional until continuous-learning Phase 5. See plan.

### B.3 decisions.md / ADR approach

idea-factory's decisions.md pattern assumes *architectural* decisions. trading-signal-bot's decisions are mostly *numerical*. Format proposal:

```markdown
## 2026-04-10: SR_PROXIMITY_PCT 3.0 → 1.5
- **Model**: SENSE
- **Metric before**: 30d winrate 52%, false-positive rate 31%
- **Metric after**: 30d winrate 58%, false-positive rate 19%
- **Evidence**: `scripts/backtest.js` on signal:log N=487
- **Trade-off**: 22% fewer signals fired (may miss weak setups)
- **Rollback**: `git revert <sha>` — no schema change
- **Invariant touched**: none
- **CEO approval**: (or: within ±10% auto-approved)
```

Numeric-first ADRs. Every parameter change gets one entry. This makes "what did we try and why did we stop" visible to the next session.

---

## C. Context Degradation

### C.1 Expected symptoms (concrete to this codebase)

- **Forgetting that DNA doesn't take `fundingData`.** `DNA.analyzeBuy(symbol, data, taCache, fundingData, marketAvgChange)` currently *accepts* those args for signature symmetry with other models. Mid-session, the agent "helpfully" starts *using* them.
- **Forgetting that `_ta-core.js` is a copy.** Agent refactors TA indicators.
- **Forgetting that consensus is count-based.** Agent starts adding `* weight` multipliers, ensemble "works better", breaks the documented count semantics everywhere it's read (5 call sites in `trading-signal.js`, `_discord-alert.js`, `signal-command.js`, `signal-briefing.js`, `_chart-generator.js`).
- **Re-tuning the same parameter to a previously-rejected value** because the tuning search history only lives in git log, which the compacted context has lost.
- **Reintroducing removed false-positive filters** because the removal commit is out of context.
- **Contradicting own earlier claim in same session** ("backtest shows improvement" → 20 messages later → "we haven't validated this").
- **Rubber-stamping backtest output** because the same session ran both the tuning and the evaluation.

### C.2 Applicable mitigations

| Symptom | idea-factory pattern | Adapted |
|---|---|---|
| Forgetting purity rules | CLAUDE.md 80-line invariants + session-start checklist | Direct transplant (B.1) |
| `_ta-core.js` drift | Protected Files + run-architect | Add to `.protected-files`; architect reviewer checks against upstream |
| Rubber-stamped backtests | Fresh Context Isolation | Backtest reviewer in worktree with zero tuning-session context |
| Re-tuning same value | Phase handoff docs | Tuning-experiment handoff (see C.3) |
| Zombie reintroduction | CONTRACT FAQ | Mandatory (B.2) |
| Mid-session self-contradiction | Fix-loop 3-attempt breaker + `project-memory` | Direct |
| Forgetting consensus semantics | CONTRACT FAQ entry + `decisions.md` | Direct |

### C.3 Context reset moments (cron-friendly equivalents)

Phase handoffs don't map because there are no phases. The natural "reset" moments here are:

1. **Per tuning experiment.** One experiment = one hypothesis about one parameter. End state: `handoff-experiment-<id>.md` capturing hypothesis, diff, backtest delta, verdict, rollback. Next session reads this BEFORE starting new experiment.
2. **Weekly baseline refresh.** Every Sunday, snapshot `stats:model:*` + `signal:log` winrate into `.project/weekly-baseline-YYYY-WW.md`. This becomes the quality-ratchet anchor for the next week.
3. **Per drift-check trigger.** If the continuous-learning plan's drift detector fires (`>15% winrate delta`), that's a forced context reset: the next session starts by reading the drift report and the freeze justification.
4. **Per model-level learning run.** `learn-dna.js` weekly, `learn-other.js` daily — each produces a handoff entry summarizing parameter changes.

### C.4 Context budget rules of thumb

Grounded in the actual file sizes (`wc -l` above: signal-engine 1116, ta-core 589, trading-signal cron 441, dna-training-data 534):

- **Never load all of `_signal-engine.js` + `_ta-core.js` + `_composite-scorer.js` simultaneously.** That's 1912 lines of dense logic — past any honest reasoning budget. Use Grep to pull only the relevant model object.
- **Per tuning session: one model at a time.** If tuning DNA, don't touch SENSE.
- **Delegate backtest execution to a subagent with fresh context.** The backtest script + `signal:log` sample is the *only* context it should have.
- **Never load `analysis/dna-v2-training.json` into the DNA tuning session.** It contains forbidden features and will contaminate reasoning.
- **If context > 60% full, write handoff-experiment.md and restart.**

---

## D. Vibe-Coding Anti-Patterns

| Anti-pattern | TSB at risk? | idea-factory coverage | Adapted mitigation |
|---|---|---|---|
| **Ghost Bug** (claim without verify) | **Very high** — tuning is inherently "should work" territory, there's no compiler to catch a bad threshold | Partial (fix-loop breaker, README v7.1 line mentioning "Ghost Bug awareness") | Backtest-or-ban rule: *no* parameter commit without `scripts/backtest.js` output pasted into commit message. CI hook rejects commits touching `_signal-engine.js` without a `Backtest:` trailer. |
| **Evaluator Leniency** (self-review) | **Very high** — "the model I just tuned scores high on my backtest" is the default failure mode | Strong (two-pass defect-first, fresh context worktree) | Direct transplant. Backtest-qa agent in worktree. Adversarial framing: "find every reason this parameter change will regress in production." |
| **Essence Drift** (silent pivot) | **Medium** — likely form is "signal bot → optimization framework → meta-learning platform". The continuous-learning plan already hints at this (Thompson sampling, DMA, Supabase schema) | Strong (essence.md + critic worktree) | Create `essence.md`: "15분마다 신호 쏘는 디스코드 봇. 학습은 보조. 절대 연구 프레임워크 아님." Critic gate checks every PR against this. |
| **Zombie Components** | **Very high** — documented examples in B.2 | Strong (CONTRACT FAQ pattern) | Direct transplant with the 7 FAQ entries above. |
| **Fix-Loop Thrashing** | **Very high** — tuning loops are the #1 failure mode | Strong (3-attempt breaker in v6.1) | Direct transplant, *hardened*: "same parameter changed 3x with no backtest improvement = STOP and escalate". |
| **Over-eager abstraction** | **Medium** — tempting to unify DNA/SENSE/QUANT/WALL/SHARK into `BaseModel`. The Python `models/` folder already started this (`base_model.py`, `multi_engine.py`) and the JS port rejected it — an agent will try to "finish the refactor" | Weak (idea-factory MVP-first philosophy implies "don't abstract", but no explicit pattern) | CLAUDE.md invariant: "5 models are intentionally independent object literals. Do not create BaseModel." |
| **Self-praise bias** (writing own passing tests) | **High** — especially likely with backtest scripts. Agent writes the script AND the assertion | Medium (fresh-context reviewer) | Backtest harness must be authored *once*, in a separate session, and then treated as immutable. Put it in `.protected-files`. |
| **Rubber-stamp reviews** (same context) | **Very high** | Strong (worktree isolation) | Direct transplant. This is the single most important pattern to adopt. |
| **Untested "should work"** (type-check = done) | **Maximum** — there's no type system here (JS, no TS) and "tests" are backtests | None directly; Playwright doesn't apply | New pattern needed: **"run-on-real-data" gate** — script that pulls last 24h of `signal:log` from Upstash and replays signal computation against it. No commit to `_signal-engine.js` merges without this. |
| **Context rot** (long-session self-contradiction) | **High** | Partial (handoffs, 80-line CLAUDE.md, `project-memory`) | See C.3 tuning-experiment handoff. `project-memory` entry per tuning experiment with the delta + verdict. |

---

## E. What idea-factory is MISSING for trading-bot DX (the most valuable section)

These are gaps where idea-factory v7.1 has *no* pattern, but trading-signal-bot DX would substantially benefit. This is the feedback loop into idea-factory v8 planning.

1. **No "numerical tuning" harness pattern.** idea-factory assumes work = file diffs. Signal bots do work = parameter deltas. v8 needs a first-class "tuning session" primitive: proposed delta → forced backtest → defect-first review → commit with evidence trailer → decisions.md entry. This would also benefit ML projects, recommendation systems, pricing engines — not just trading bots.

2. **No audit-log exit-0 PreToolUse hook.** HARNESS-GUIDE.md line 200 explicitly acknowledges this is "out of scope for v7.1" and `check-careful.sh` is "retained for future rewrite". For any project where commands have real-world cost (deploys, payments, live messages, DB writes), this is the single biggest missing piece. v8 priority.

3. **No `.protected-files` entry validator.** Currently `.protected-files` is a plain list. Numeric-heavy projects need **"what constitutes a change worth flagging"** metadata per file — e.g., "any `*_PCT` constant change > ±10%" vs "any import change". idea-factory's architect trigger is binary; it should be rule-driven.

4. **No quality-ratchet metrics for continuous-output systems.** idea-factory's ratchet assumes metrics are measured at commit time (bundle size, test count). Signal bots produce *runtime* metrics (daily winrate, false-positive rate, signal count). v8 needs a "runtime ratchet" concept: pull metrics from a state store, compare over time windows, block merges that regress production-observed metrics.

5. **No CONTRACT-enforcement at AST level.** The FAQ pattern is prose. Numeric projects need machine-checkable invariants, e.g. "this function signature must not include `taCache` and `fundingData` parameters" — `ast_grep_search` could enforce this in a pre-commit hook. idea-factory provides the concept but not the enforcement primitive.

6. **No "cron-bot" project template.** idea-factory's templates assume user-facing UI with Playwright QA. Cron bots need: audit log, backtest harness, runtime metric collection, rollback script, Discord-as-QA-surface. A `templates/cron-bot/` sibling to the current implicit "web app" template would be valuable.

7. **No "subject of study" pattern for copied code.** `_ta-core.js` is copied from another repo. idea-factory has no mechanism for "this file is a copy, drift from upstream is a bug". v8 could introduce a `COPIED-FROM.md` file + a CI check that diffs against the upstream repo.

8. **Reviewer gate is a fixed count (4).** Should be *rule-driven by file type*: UI change → qa-tester required; numeric-only diff → backtest-qa required; doc-only → no gate. trading-signal-bot specifically needs "single-file numeric diff → 2 reviewers" as a recognized class.

9. **No session-memory for failed attempts.** idea-factory has `project-memory` for durable facts. It's missing a "tried-and-failed" ledger so the next session doesn't re-try "set MOMENTUM_ENTRY_PCT to 2.5" for the fourth time.

---

## F. Recommended experiments (not commitments)

1. **Drop idea-factory v7.1 CLAUDE.md + 80-line limit into trading-signal-bot.** Use the skeleton in B.1. Cheapest, highest leverage.
2. **Author `scripts/backtest-against-signal-log.js`** — pure: reads `signal:log` from Upstash, replays with current engine, outputs winrate. This becomes the backtest-qa tool. One-off, then immutable, then added to `.protected-files`.
3. **Author `CONTRACT.md`** with the 7 FAQ entries in B.2. This is a 30-min task and prevents the largest class of zombie bugs.
4. **Prototype a 2-reviewer gate** (`architect` + `backtest-qa`) as worktree scripts. Measure: does it catch regressions during tuning? Compare to current "autopilot with no gate" baseline.
5. **Prototype the exit-0 audit-log hook** (the thing idea-factory v7.1 shelved). If it works well here, feed it back into idea-factory v8 as the default.
6. **Run one tuning experiment under the proposed protocol end-to-end** — state hypothesis, change one parameter, run backtest, commit with evidence trailer, write handoff-experiment.md. See if the loop actually closes without thrashing.
7. **Do NOT adopt Playwright QA.** Doesn't apply.
8. **Do NOT adopt phase handoffs verbatim.** Use tuning-experiment handoffs instead.

---

## References

- `/Users/bong/trading-signal-bot/api/_signal-engine.js:159` — DNA model object with hardcoded thresholds
- `/Users/bong/trading-signal-bot/api/_signal-engine.js:164-170` — existing comment warning "Phase 2 TODO" for the purity invariant
- `/Users/bong/trading-signal-bot/api/_signal-engine.js:213` — MAJOR-3 threshold change (zombie candidate)
- `/Users/bong/trading-signal-bot/api/_signal-engine.js:419` — MAJOR-6 SR_PROXIMITY change (zombie candidate)
- `/Users/bong/trading-signal-bot/api/_signal-engine.js:592` — Bug3 SHARP_DROP change (zombie candidate)
- `/Users/bong/trading-signal-bot/api/_signal-engine.js:873` — `MODELS = [DNA, WALL_ST, SENSE, QUANT, SHARK]`
- `/Users/bong/trading-signal-bot/api/_signal-engine.js:876-1002` — count-based consensus (no weights)
- `/Users/bong/trading-signal-bot/api/_composite-scorer.js:12` — TA/Flow/Sentiment `WEIGHT` (confusable with ensemble weights)
- `/Users/bong/trading-signal-bot/api/_ta-core.js` — 589 lines copied from market-dashboard-v5 (zombie risk)
- `/Users/bong/trading-signal-bot/api/cron/trading-signal.js:226-227` — entry point calling `analyzeBuySignals/analyzeSellSignals`
- `/Users/bong/trading-signal-bot/README.md:15` — "마켓레이더v5의 taCalculator.js를 복사한" (copy declaration)
- `/Users/bong/trading-signal-bot/README.md:63` — CEO-only deploy rule (currently unenforced)
- `/Users/bong/trading-signal-bot/.omc/plans/continuous-learning-architecture.md` — 3-layer DNA purity defense + Phase 1-5 roadmap
- `/Users/bong/idea-factory/skills/start-company/HARNESS-GUIDE.md:89` — Fresh Context Isolation rationale
- `/Users/bong/idea-factory/skills/start-company/HARNESS-GUIDE.md:160` — v7.1 runtime safety rationale (the gap this report flags)
- `/Users/bong/idea-factory/skills/start-company/HARNESS-GUIDE.md:196` — exit-0 advisory hook marked "out of scope"
- `/Users/bong/idea-factory/skills/start-company/HARNESS-GUIDE.md:286` — Protected Files pattern
- `/Users/bong/idea-factory/README.md:22` — v7.1 bypassPermissions + deny-list design
