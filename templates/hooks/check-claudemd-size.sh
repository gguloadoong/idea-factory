#!/bin/bash
# check-claudemd-size.sh — PostToolUse(Write|Edit) hook: keep CLAUDE.md lean
#
# WHY THIS EXISTS:
# CLAUDE.md is loaded into context on EVERY conversation turn. A bloated CLAUDE.md
# wastes tokens and slows down every single interaction. The 80-line limit forces
# progressive disclosure: keep CLAUDE.md as an index/overview, move details to
# separate files (AGENTS.md, docs/, etc.).
#
# Without this hook, CLAUDE.md tends to grow unboundedly as features are added,
# eventually becoming a multi-hundred-line file that eats context budget.
#
# TRIGGER: PostToolUse on Write|Edit
# PRINCIPLE: Silent Success, Loud Failure

# Graceful degradation if jq is missing
command -v jq &>/dev/null || exit 0

# Read tool input from stdin
INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

# Extract file_path from tool input
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE_PATH" ] && exit 0

# Only check files named exactly CLAUDE.md (not HARNESS-GUIDE.md, not other .md)
BASENAME=$(basename "$FILE_PATH")
if [ "$BASENAME" != "CLAUDE.md" ]; then
  exit 0
fi

# File must exist to count lines
if [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

LINE_COUNT=$(wc -l < "$FILE_PATH" | tr -d ' ')
LIMIT=${CLAUDEMD_SIZE_LIMIT:-80}

if [ "$LINE_COUNT" -gt "$LIMIT" ]; then
  echo "[claudemd-size] CLAUDE.md is ${LINE_COUNT} lines (limit: ${LIMIT}). Use progressive disclosure — move details to separate files."
fi

# Silent on success (no output when under limit)
exit 0
