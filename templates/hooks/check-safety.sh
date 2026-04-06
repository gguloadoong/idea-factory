#!/bin/bash
# check-safety.sh — PreToolUse hook: runtime guardrails for dangerous operations
#
# WHY THIS EXISTS (for GitHub readers):
# Claude Code Harness (github.com/Chachamaru127/claude-code-harness) enforces 13 safety
# rules (R01-R13) via TypeScript. This is a lightweight shell equivalent that catches
# the most critical risks without requiring Node.js.
#
# Inspired by: Anthropic harness engineering research
# https://www.anthropic.com/engineering/harness-design-long-running-apps
#
# HOW IT WORKS:
# This script runs BEFORE every Bash command Claude executes.
# If it detects a dangerous pattern, it forces Claude to ASK the user for permission
# instead of running silently. Safe commands pass through without interruption.
#
# RULES:
# S01: Block sudo commands (privilege escalation)
# S02: Block .env file commits (secret exposure)
# S03: Block force push (history destruction)
# S04: Block hard reset to main (work destruction)
# S05: Block --no-verify (hook bypass)
# S06: Block direct push to main/master (process bypass)
# S07: Block credential file writes (secret exposure)
# S08: Block rm -rf on project root or home (catastrophic deletion)

command -v jq &>/dev/null || exit 0
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[ -z "$COMMAND" ] && exit 0

# Each rule: pattern + human-readable reason
declare -A RULES
RULES["sudo "]="S01: sudo detected — privilege escalation risk"
RULES["git add.*\.env"]="S02: staging .env file — secrets will be committed"
RULES["git commit.*\.env"]="S02: committing .env file — secrets will be exposed"
RULES["git push.*--force"]="S03: force push — will destroy remote history"
RULES["git push.*-f "]="S03: force push (short flag) — will destroy remote history"
RULES["git reset --hard.*(main|master)"]="S04: hard reset to main — will destroy local changes"
RULES["--no-verify"]="S05: skipping git hooks — safety checks will be bypassed"
RULES["--no-gpg-sign"]="S05: skipping GPG signing — commit verification bypassed"
RULES["git push.*(origin|upstream).*(main|master)[^/]"]="S06: direct push to main/master — use PR workflow"
RULES["\.pem"]="S07: operation on certificate file — verify this is intentional"
RULES["\.key"]="S07: operation on key file — verify this is intentional"
RULES["credentials"]="S07: operation involving credentials — verify no secrets exposed"
RULES["rm -rf /"]="S08: recursive delete on root — catastrophic"
RULES["rm -rf ~"]="S08: recursive delete on home — catastrophic"
RULES["rm -rf \\."]="S08: recursive delete on current directory — verify this is intentional"

for pattern in "${!RULES[@]}"; do
  if echo "$COMMAND" | grep -qiE "$pattern"; then
    reason="${RULES[$pattern]}"
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"%s"}}\n' "$reason"
    exit 0
  fi
done

# Silent on success — context-efficient (only errors produce output)
exit 0
