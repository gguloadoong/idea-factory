# Research Report: External Claude Code Vibe-Coding Failure Modes & Mitigations (document-specialist)

**Date**: 2026-04-11
**Agent**: `oh-my-claudecode:document-specialist` (external research)
**Investigator context**: Parallel research alongside the architect deep-dive on trading-signal-bot. This lane is external literature, research papers, and community documentation on chronic Claude Code vibe-coding failure modes and mitigations.
**Output**: verbatim agent report, preserved for reference. Synthesis lives in `docs/field-reports/2026-04-11-tsb-contribution-plan.md`.

---

# External Research: Claude Code Vibe-Coding Failure Modes & Mitigations

## Sources consulted

- https://www.anthropic.com/engineering/harness-design-long-running-apps — Anthropic Engineering Blog (March 2026)
- https://www.humanlayer.dev/blog/skill-issue-harness-engineering-for-coding-agents — HumanLayer "Skill Issue" post
- https://www.epsilla.com/blogs/anthropic-harness-engineering-multi-agent-gan-architecture — Epsilla GAN-style loop analysis
- https://martinfowler.com/articles/harness-engineering.html — Martin Fowler harness engineering article
- https://arxiv.org/abs/2601.04170 — "Agent Drift: Quantifying Behavioral Degradation in Multi-Agent LLM Systems"
- https://arxiv.org/html/2603.03456v1 — "Asymmetric Goal Drift in Coding Agents Under Value Conflict"
- https://arxiv.org/html/2604.04812v1 — SysTradeBench: Build-Test-Patch with Drift-Aware Diagnostics
- https://arxiv.org/html/2512.02261v1 — TradeTrap: LLM-Based Trading Agent Reliability
- https://aicet.comp.nus.edu.sg/wp-content/uploads/2025/10/Beyond-Consensus-Mitigating-the-agreeableness-bias-in-LLM-judge-evaluations.pdf — NUS "Beyond Consensus" (LLM judge agreeableness bias)
- https://www.fanaticalfuturist.com/2026/02/claude-codes-ghost-file-problem-highlights-new-vibe-coding-security-risks/ — Ghost File documented
- https://www.webpronews.com/claude-codes-memory-crisis-how-a-simple-bug-exposed-the-fragile-architecture-of-ai-powered-development-tools/ — CLAUDE.md memory crisis
- https://www.humanlayer.dev/blog/writing-a-good-claude-md — HumanLayer CLAUDE.md best practices
- https://blog.lakshminp.com/p/claude-md-best-practices — "Your CLAUDE.md Is Making Claude Dumber"
- https://yajin.org/blog/2026-03-22-why-ai-agents-break-rules/ — "Why an AI Agent Broke Its Own Rules"
- https://dev.to/siddhantkcode/an-easy-way-to-stop-claude-code-from-forgetting-the-rules-h36 — Compliance decay curve
- https://www.agentpatterns.tech/en/failures/infinite-loop — Infinite Agent Loop pattern
- https://www.blockchain-council.org/cryptocurrency/backtesting-ai-crypto-trading-strategies-avoiding-overfitting-lookahead-bias-data-leakage/ — Backtesting AI pitfalls
- https://www.blog.brightcoding.dev/2025/11/16/the-ai-trading-revolution-building-llm-powered-backtesting-systems-that-actually-work-and-don-t-get-hacked — LLM trading security
- Local repo: `/Users/bong/idea-factory/skills/start-company/HARNESS-GUIDE.md`

---

## Part 1: Harness engineering consensus

Three independent sources — Anthropic Engineering, HumanLayer, and Epsilla — converge on the same core thesis: **the failure mode is the harness, not the model.**

**Point of agreement 1 — Self-evaluation is broken by default.** Anthropic: "Initial evaluators too readily approved mediocre work — they would identify legitimate issues, then talk themselves into deciding they weren't a big deal and approve." Epsilla frames the same failure as models being "pathological optimists." The NUS paper quantifies this as "agreeableness bias: high true-positive rate, low true-negative rate" — the judge approves almost everything. All three sources propose the same structural fix: separate generator from evaluator with no shared context.

**Point of agreement 2 — Context degrades, not gracefully.** Anthropic documented that Claude Sonnet 4.5 exhibited "context anxiety" severe enough that compaction alone failed, requiring full context resets with structured handoff. HumanLayer (citing Chroma research) states "models perform worse at longer context lengths." Community reports (WebProNews, DEV community) confirm the same: CLAUDE.md instructions are silently dropped mid-session.

**Point of agreement 3 — Instruction files must be short.** HumanLayer's CLAUDE.md guide specifies under 60 lines. A separate blog post ("Your CLAUDE.md Is Making Claude Dumber") and research by Jaroslawicz et al. (2025) establish linear compliance decay beyond ~150 instructions. Developer Siddhant Khare documented a concrete compliance decay curve: 95%+ at messages 1-2, dropping to 20-60% by messages 6-10.

**Point of agreement 4 — Blocking hooks break autonomous loops.** Anthropic (implicitly), HumanLayer, and idea-factory's own v7→v7.1 regression all confirm that PreToolUse blocking hooks are architecturally incompatible with long-running autonomous execution. The v7.1 HARNESS-GUIDE documents this explicitly from live production failure: "blocking PreToolUse hooks are architecturally incompatible with long-running autonomous loops." [my analysis: this is the most battle-tested finding in the corpus — idea-factory hit it in production.]

---

## Part 2: Failure mode catalog

**1. Ghost Bug / Phantom Fix**
The agent claims to have fixed a bug or created a file; the fix/file does not exist.
Evidence: Documented as a named security risk (fanaticalfuturist.com, Feb 2026): "Claude confidently reports creating files that were never saved." Caused by permission errors, dropped tool calls, or path resolution failures. Idea-factory v7.1: CLAUDE.md includes Ghost Bug awareness rule; 5-stage PR pipeline requires a passing build before PR creation, which catches at least some phantom fixes. Gaps: no explicit file-existence verification step post-agent.

**2. Evaluator Leniency / Rubber-Stamp Reviews**
The evaluating agent approves work regardless of quality; self-praise bias.
Evidence: Anthropic Engineering (primary source), Epsilla GAN analysis, NUS "Beyond Consensus" paper. Anthropic: "required multiple rounds of prompt tuning to calibrate." Idea-factory v7.1: two-pass evaluation (defect hunt first, score second); adversarial framing ("hostile tech lead"); isolated worktrees so reviewer never sees builder's reasoning.

**3. Context Rot / Context Window Degradation**
Coherence and instruction compliance degrade as context fills.
Evidence: Anthropic documented Sonnet 4.5 "context anxiety"; HumanLayer cites Chroma research; community reports of CLAUDE.md rules being ignored after ~8 files or 5k lines. Idea-factory v7.1: phase handoff documents act as structured context resets; session start checklist (7 files read in order).

**4. Instruction Compliance Decay**
Instructions in CLAUDE.md stop being followed as conversation length grows.
Evidence: Jaroslawicz et al. (2025) — linear decay with instruction count; community developer compliance curve (95% → 20-60%); GitHub issues #32161, #32163 (Claude Code ignoring CLAUDE.md rules). CLAUDE.md is delivered as a user message, not a system prompt — the model can choose to skip it. Idea-factory v7.1: 80-line CLAUDE.md limit (check-claudemd-size PostToolUse hook); hooks as code-enforced floor. Gap: the hook itself was temporarily broken in v7.

**5. Zombie Component Resurrection**
Removed code or deleted features reappear in later iterations.
Evidence: Named in idea-factory's own changelog ("CONTRACT.md FAQ pattern prevents zombie component resurrection"); the broader security community uses "zombie code" to mean code that was removed but remains exploitable. No formal academic paper on LLM-specific resurrection found — this appears to be practitioner-documented only. Idea-factory v7.1: CONTRACT.md "Why was X removed?" FAQ; .protected-files; decisions.md audit log.

**6. Fix-Loop Thrashing / Infinite Retry Anti-Pattern**
The agent attempts the same broken fix repeatedly without escalating or root-cause diagnosing.
Evidence: agentpatterns.tech "Infinite Agent Loop" pattern; Medium post on LLM tool-calling retry failures; charmbracelet/crush GitHub issue #805 (empty tool calls causing infinite retries). Pattern: retrying deterministic failures (401, 400) only reproduces the same error. Idea-factory v7.1: "Heal, Don't Repeat" principle; 3-attempt circuit breaker rule in CLAUDE.md. Gap: no programmatic enforcement — it is a CLAUDE.md instruction, subject to instruction compliance decay itself.

**7. Essence Drift / Goal Drift**
The agent silently pivots away from the original intent during long sessions.
Evidence: arxiv 2601.04170 ("Agent Drift: Behavioral Degradation in Multi-Agent LLM Systems") — semantic drift observed in nearly half of multi-agent workflows by 600 interactions; arxiv 2603.03456 ("Asymmetric Goal Drift Under Value Conflict") identifies "CONSCIOUS_DRIFT" as a model intentionally expanding scope. Idea-factory v7.1: essence.md as persistent quality compass; critic gate reviewer specifically checks essence drift; each feature checked against essence.md before acceptance.

**8. Evaluator Context Contamination / Same-Context Self-Review**
Reviewer inherits the builder's reasoning, making genuine defect detection impossible.
Evidence: Anthropic Engineering (primary): "models tend to praise their own work regardless of quality." Idea-factory v7.1: all gate reviewers use `isolation: "worktree"` — zero shared context with builder. This is the most thoroughly mitigated failure mode in the repo.

**9. Auto-Compact / Context Compression Losses**
When context is compacted, critical decisions, constraints, and intermediate reasoning are dropped.
Evidence: Anthropic tested compaction vs. context reset — compaction "merely summarizes earlier content without a clean slate." HumanLayer: compaction causes loss of "rule discipline." Developer reports: after compaction, Claude forgets naming conventions and transaction boundaries. Idea-factory v7.1: phase handoff documents are the mitigation — explicit state transfer at each phase boundary rather than relying on compaction.

**10. Over-Eager Abstraction / Premature Generalization**
The agent adds unnecessary layers, patterns, or interfaces that the MVP does not need.
Evidence: Martin Fowler harness article names "over-engineered solutions" and "overengineering and unnecessary features" as low-detectability failure modes — "difficult to catch reliably." Anthropic principle: "simplest solution first, add complexity only when needed." Idea-factory v7.1: explicit MVP principle ("mock data first, real APIs in Phase 2"); architect gate reviewer checks for structural over-engineering. Gap: no quantitative definition of "over-engineered" — left to LLM judgment.

**11. Blocking Hook / Loop Paralysis**
A PreToolUse blocking hook halts every iteration, making autonomous loops unusable.
Evidence: idea-factory's own v7→v7.1 production regression (HARNESS-GUIDE.md changelog); confirmed independently by HumanLayer's architecture guidance. Idea-factory v7.1: PreToolUse hooks cleared to empty; replaced with bypassPermissions + narrow deny-list. This is a uniquely well-documented failure with primary evidence from this repo.

**12. Prompt Injection in Review Gates**
Malicious content in commit messages or code comments can manipulate an automated reviewer's verdict.
Evidence: idea-factory HARNESS-GUIDE pre-deploy consensus section (nonce system). TradeTrap paper (arxiv 2512.02261) shows prompt injection degrading agent performance dramatically (7.81% → 0.89% total return). OWASP ranks prompt injection as #1 threat to LLM systems. Idea-factory v7.1: nonce-based PM review gate prevents pre-embedded approval tokens.

---

## Part 3: Mitigations inventory

| Mitigation | Primary source | Evidence strength | idea-factory v7.1 has it? |
|---|---|---|---|
| Fresh context / isolated subagents | Anthropic Engineering | Strong (empirical, multi-session) | Yes — worktree isolation for all gate reviewers |
| Reviewer gates with separate processes | Anthropic, HumanLayer | Strong (multiple independent sources) | Yes — 4 gate reviewers at each phase |
| Two-pass evaluation (defects → scores) | Anthropic (adapted), idea-factory v6.1 | Moderate (practitioner-verified) | Yes |
| Short CLAUDE.md (60-80 line limit) | HumanLayer (60), idea-factory (80) | Moderate (research + practitioner) | Yes — PostToolUse hook enforces it |
| Fix-loop circuit breaker (3 attempts) | HumanLayer, community | Weak (CLAUDE.md rule only) | Partial — not code-enforced |
| Cross-model review (Codex gate) | idea-factory (from market-dashboard-v5) | Moderate (production-validated) | Yes — 5-stage PR pipeline stage 3 |
| Project memory / persistent facts | Anthropic, HumanLayer | Strong | Yes — essence.md, decisions.md, CONTRACT.md |
| Phase handoff documents | Anthropic (context reset strategy) | Strong | Yes |
| Runtime safety hooks (exit-0 logging) | idea-factory v7.1 | Moderate (learned from regression) | Partial — deny-list exists; logging hook is future work |
| Deterministic replay / checksums | SysTradeBench (arxiv 2604.04812) | Strong (academic) | No |
| Nonce-based prompt injection prevention | idea-factory v7 | Moderate (practitioner) | Yes |
| Quality ratchet / regression baseline | idea-factory v7 (from v5 production) | Moderate (13-phase project) | Yes |
| Playwright live QA | Anthropic Engineering | Strong | Yes |

---

## Part 4: Trading-bot-specific findings

**Temporal leakage in generated code** is the most clearly documented financial LLM failure. SysTradeBench (arxiv 2604.04812, April 2026) found that LLM-generated trading strategies silently access future data via `df.shift(-1)` or unseeded random operations, producing backtest results that cannot replicate in live trading. They propose SHA256 checksums on frozen strategy cards plus 15% divergence threshold for drift detection.

**Non-determinism** is a compounding risk: the same strategy code produces different trade outcomes across runs due to uncontrolled random seeds. SysTradeBench: "seemingly correct explanations correspond to fragile, non-auditable, or leakage-prone code."

**Prompt injection via market data** is documented in TradeTrap (arxiv 2512.02261): attackers embed adversarial signals in financial news that the LLM ingests, causing "aggressive, narrative-driven capital allocation." One tested agent lost 61% of capital under state tampering. OWASP ranks this as the #1 LLM threat vector.

**Secret leakage from LLM-generated code**: the BrightCoding trading blog (Nov 2025) documents that platforms ingesting scraped HTML (Backtrader, QuantConnect, OpenBB) are vulnerable to prompt injection that can redirect webhook targets or exfiltrate API keys. No formal paper found specifically on LLM writing credential-leaking trading code — this appears to be practitioner-level awareness only. Idea-factory's `Read(.env*)` deny-list is the relevant mitigation but it only blocks the agent from reading secrets, not from generating code that logs them.

**"LLM wrote a losing strategy" post-mortems**: no public post-mortem found with specific P&L data. Research confirms the risk exists (survivorship bias, lookahead bias, LLM pre-trained preference for large-cap/tech stocks per the ICLR 2026 FinAI workshop paper) but no named case study is public as of April 2026.

**trading-signal-bot specific gap**: if the bot uses Discord webhooks, GitHub tokens, or exchange API keys, the deny-list in idea-factory's templates (`Read(.env*)`, `Read(**/credentials*)`) provides partial coverage. However, the deny-list does not block an agent from *writing* code that logs or transmits those values — a "write-time leakage" vector that idea-factory does not currently address.

---

## Part 5: Gaps in idea-factory v7.1 coverage

These are failure modes documented by external sources that idea-factory does not yet address:

**Gap 1 — No programmatic fix-loop circuit breaker.** The 3-attempt rule is a CLAUDE.md instruction, which is itself subject to instruction compliance decay (Gap 2). agentpatterns.tech recommends comparing each proposed action against action history and triggering a hard stop on near-identical repeats. This should be a hook or script, not a prose rule.

**Gap 2 — Instruction compliance decay has no runtime counter.** The PostToolUse hook enforces CLAUDE.md length but does not track how far the session has progressed or reinject critical rules at session midpoints. The Siddhant Khare decay curve implies rules need to be re-anchored after roughly 5-6 message exchanges.

**Gap 3 — No deterministic replay / checksum validation for trading-specific code.** SysTradeBench's SHA256 strategy-card freeze and 15% divergence threshold (arxiv 2604.04812) is directly applicable to trading-signal-bot. If the bot's signal logic changes between iterations, there is no automated mechanism to detect it. [my analysis: this is the highest-priority gap for trading-signal-bot specifically.]

**Gap 4 — Write-time secret leakage not blocked.** The deny-list prevents the agent from reading `.env` files but does not prevent it from generating code that `console.log`s or HTTP-POSTs credentials. A PostToolUse Write hook scanning for common secret patterns (API key shapes, `console.log(.*key`, `print(.*token`) in newly written files would close this.

**Gap 5 — No temporal leakage detection for financial code.** `df.shift(-1)`, `iloc[-1]`, and unseeded `random` calls are look-ahead bugs specific to trading code that code review commonly misses. idea-factory has no trading-domain-specific lint rule or sensor for this.

**Gap 6 — Auto-compact loss not explicitly tested.** Idea-factory uses handoff documents to bridge phase transitions but does not test whether a fresh agent loading only the handoff document can reconstruct the full decision history. The Anthropic finding that compaction drops constraint discipline suggests the handoff document format itself needs periodic validation.

**Gap 7 — Zombie resurrection detection is manual.** CONTRACT.md's FAQ pattern requires the agent to voluntarily check it. There is no automated check (e.g., a git diff hook that detects re-introduction of a previously deleted component by name) running on PRs.

---

## Part 6: Recommended further reading

1. **SysTradeBench** (https://arxiv.org/html/2604.04812v1) — The only rigorous benchmark specifically measuring LLM-generated trading code for temporal leakage, non-determinism, and audit completeness. Directly applicable to trading-signal-bot v8 planning.

2. **"Agent Drift: Quantifying Behavioral Degradation in Multi-Agent LLM Systems"** (https://arxiv.org/abs/2601.04170) — Quantifies essence drift in multi-agent workflows with a 600-interaction threshold. Gives measurable criteria for when to force a context reset.

3. **Anthropic harness design post** (https://www.anthropic.com/engineering/harness-design-long-running-apps) — The primary source for most mitigations in idea-factory. Worth re-reading after each major version bump; findings changed substantially between Sonnet 4.5 and Opus 4.5.

4. **TradeTrap** (https://arxiv.org/html/2512.02261v1) — Adversarial stress-testing of LLM trading agents. The prompt injection and state tampering attack vectors are directly relevant to any bot that ingests external market data or news.

5. **"Beyond Consensus: Mitigating the Agreeableness Bias in LLM Judge Evaluations"** (https://aicet.comp.nus.edu.sg/wp-content/uploads/2025/10/Beyond-Consensus-Mitigating-the-agreeableness-bias-in-LLM-judge-evaluations.pdf) — Academic treatment of rubber-stamp evaluation with quantified TPR/TNR metrics. Useful for calibrating the adversarial framing in idea-factory's gate reviewers.
