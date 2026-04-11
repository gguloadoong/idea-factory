#!/usr/bin/env bash
# invariant-exit-zero.sh — v7 regression guard
#
# INVARIANT: Every templates/hooks/*.sh script MUST return exit 0
# regardless of input. No exceptions.
#
# Rationale: v7 (2026-04-04 → 2026-04-09) shipped blocking PreToolUse
# hooks (check-careful.sh + check-safety.sh) that returned non-zero on
# risky commands. Claude Code interpreted this as "ask user to approve",
# producing approval prompts on every single Bash command in downstream
# projects. Autonomous workflows were paralyzed until v7.1 hotfix.
#
# v7.1 + v8 contract: hooks OBSERVE but NEVER HALT. Commands that must
# be blocked belong in `permissions.deny` in settings.json, not here.
#
# This script runs each hook against a battery of adversarial inputs and
# fails if any returns non-zero. It is the last line of defense against
# v7-style regression.

set +e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS_DIR="$ROOT/templates/hooks"

if [ ! -d "$HOOKS_DIR" ]; then
  echo "  FAIL: $HOOKS_DIR does not exist"
  exit 1
fi

# Input battery designed to provoke failure in a brittle hook
INPUTS=(
  ''
  '{}'
  'null'
  '[]'
  'not valid json'
  '{"tool_input":{"command":"ls"}}'
  '{"tool_input":{"command":"vercel --prod"}}'
  '{"tool_input":{"command":"redis-cli FLUSHDB"}}'
  '{"tool_input":{"command":"echo \"quoted\""}}'
  '{"tool_input":{"command":""}}'
  '{"tool_input":null}'
  '{"tool_input":{"command":"git push --force"}}'
  '{"tool_input":{"command":"rm -rf /tmp/test"}}'
)

FAILED=0
HOOK_COUNT=0

# Per-hook 5-second timeout wrapper. If `timeout` is unavailable (e.g.
# minimal environments), fall back to running without it. This protects
# CI from hangs if a future hook has a code path that blocks (e.g.
# `tsc --noEmit` that resolves slowly).
run_hook() {
  local hook="$1"
  if command -v timeout >/dev/null 2>&1; then
    timeout 5s bash "$hook" >/dev/null 2>&1
  else
    bash "$hook" >/dev/null 2>&1
  fi
}

# Generate 1MB of "A" characters using shell tools (no python3 dependency).
# `head -c` + `tr` is portable across GNU and BSD systems.
gen_1mb() {
  head -c 1000000 /dev/zero 2>/dev/null | tr '\0' 'A' 2>/dev/null
}

# Find all .sh files in templates/hooks/ (ignore .bak files)
while IFS= read -r hook; do
  [ -f "$hook" ] || continue
  hook_name=$(basename "$hook")
  HOOK_COUNT=$((HOOK_COUNT + 1))

  # Test each predefined input
  for i in "${!INPUTS[@]}"; do
    input="${INPUTS[$i]}"
    printf '%s' "$input" | run_hook "$hook"
    rc=$?
    if [ "$rc" -ne 0 ]; then
      preview=$(printf '%s' "$input" | head -c 60)
      echo "  FAIL: $hook_name exited $rc with input[$i]: $preview"
      FAILED=$((FAILED + 1))
    fi
  done

  # Edge case: binary garbage
  head -c 200 /dev/urandom | run_hook "$hook"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "  FAIL: $hook_name exited $rc with binary garbage"
    FAILED=$((FAILED + 1))
  fi

  # Edge case: 1MB oversized input (uses shell tools, no python3)
  gen_1mb | run_hook "$hook"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "  FAIL: $hook_name exited $rc with 1MB oversized input"
    FAILED=$((FAILED + 1))
  fi

  # Edge case: control characters
  printf '\x01\x02\x03\x04\x00binary\x07\xff' | run_hook "$hook"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "  FAIL: $hook_name exited $rc with control chars"
    FAILED=$((FAILED + 1))
  fi

done < <(find "$HOOKS_DIR" -maxdepth 1 -name "*.sh" -not -name "*.bak" -not -name "*.bak.*" -type f | sort)

if [ "$HOOK_COUNT" -eq 0 ]; then
  echo "  (no hooks in $HOOKS_DIR)"
  exit 0
fi

if [ "$FAILED" -gt 0 ]; then
  echo ""
  echo "═══════════════════════════════════════════════════════════"
  echo "v7 REGRESSION GUARD: $FAILED violation(s) in $HOOK_COUNT hook(s)"
  echo "═══════════════════════════════════════════════════════════"
  echo ""
  echo "Hooks MUST always exit 0. See:"
  echo "  - skills/start-company/HARNESS-GUIDE.md (Runtime Safety section)"
  echo "  - docs/field-reports/2026-04-11-v7-propagation-postmortem.md"
  echo ""
  echo "Fix: wrap the failing code path in '|| true' or ensure the hook"
  echo "has 'trap \"exit 0\" ERR EXIT' and a final explicit 'exit 0'."
  exit 1
fi

echo "v7 regression guard: $HOOK_COUNT hook(s) verified, all exit 0 on adversarial inputs ✓"
exit 0
