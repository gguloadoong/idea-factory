#!/bin/bash
# check-gate-isolation.sh — PreToolUse(Agent) hook: enforce worktree isolation for gate reviewers
#
# WHY THIS EXISTS:
# Gate reviewers (architect, critic, code-reviewer, qa-tester) must run in isolated
# worktrees to prevent them from accidentally modifying the working directory during
# review. Without this hook, a gate reviewer could read/write to the same tree the
# executor is working in, breaking the separation between "author" and "reviewer."
#
# This turns the CLAUDE.md instruction "use worktree isolation" into an actual lock:
# Claude cannot proceed without explicitly setting isolation: worktree.
#
# TRIGGER: PreToolUse on Agent tool
# PRINCIPLE: Silent Success, Loud Failure

# Graceful degradation if jq is missing
command -v jq &>/dev/null || exit 0

# Read tool input from stdin
INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

# Extract the agent prompt from tool input
PROMPT=$(echo "$INPUT" | jq -r '.tool_input.prompt // empty' 2>/dev/null)
[ -z "$PROMPT" ] && exit 0

# Check if this is a gate review agent
# Must match BOTH: an agent role keyword AND a gate keyword
IS_GATE_AGENT=false

if echo "$PROMPT" | grep -qiE '(architect|critic|code-reviewer|qa-tester)'; then
  if echo "$PROMPT" | grep -qiE '(Gate|VALIDATE|gate)'; then
    IS_GATE_AGENT=true
  fi
fi

# Not a gate agent — pass silently
if [ "$IS_GATE_AGENT" = false ]; then
  exit 0
fi

# It IS a gate agent — verify worktree isolation is set
ISOLATION=$(echo "$INPUT" | jq -r '.tool_input.isolation // empty' 2>/dev/null)

if [ "$ISOLATION" != "worktree" ]; then
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"Gate reviewer must run in isolated worktree. Add isolation: worktree"}}\n'
  exit 0
fi

# Gate agent with worktree isolation — pass silently
exit 0
