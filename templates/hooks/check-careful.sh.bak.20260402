#!/bin/bash
# check-careful.sh — PreToolUse(Bash) hook: detect dangerous commands
command -v jq &>/dev/null || exit 0
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
DANGEROUS=("rm -rf" "DROP TABLE" "DROP DATABASE" "git push.*--force" "git reset --hard" "kubectl delete")
for p in "${DANGEROUS[@]}"; do
  if echo "$COMMAND" | grep -qiE "$p"; then
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"Dangerous command detected: %s"}}\n' "$p"
    exit 0
  fi
done
exit 0
