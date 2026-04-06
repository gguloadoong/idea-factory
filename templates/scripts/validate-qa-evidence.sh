#!/bin/bash
# validate-qa-evidence.sh — Verify qa-tester actually used Playwright (not just code review)
#
# WHY THIS EXISTS:
# The qa-tester gate is supposed to run real browser tests via Playwright.
# Without this validation, qa-tester can pass the gate by simply reading code
# and saying "looks good" — which defeats the purpose of having a QA gate.
# This script checks the qa-tester's output for evidence of actual browser interaction.
#
# USAGE: bash scripts/validate-qa-evidence.sh <path-to-qa-output>
# EXIT:  0 = evidence found (silent), 1 = no evidence (loud failure)
#
# CALLED FROM: SKILL.md Gate section instructs running this after qa-tester completes

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "[qa-evidence] Usage: validate-qa-evidence.sh <qa-output-file>" >&2
  exit 1
fi

FILE="$1"

if [ ! -f "$FILE" ]; then
  echo "[qa-evidence] File not found: $FILE" >&2
  exit 1
fi

# Evidence keywords that indicate real Playwright usage
# Each keyword maps to actual Playwright API or browser interaction
EVIDENCE_KEYWORDS=(
  "screenshot"      # page.screenshot() or screenshot references
  "browser"         # browser launch/context
  "clicked"         # user interaction evidence
  "navigated"       # page navigation
  "Playwright"      # explicit tool mention
  "page\."          # Playwright page API calls (page.goto, page.click, etc.)
  "locator"         # Playwright locator API
  "expect(page"     # Playwright assertion
)

FOUND=0
for keyword in "${EVIDENCE_KEYWORDS[@]}"; do
  if grep -qiE "$keyword" "$FILE" 2>/dev/null; then
    FOUND=$((FOUND + 1))
  fi
done

if [ "$FOUND" -eq 0 ]; then
  echo "[qa-evidence] qa-tester did not use Playwright. Code-only review is insufficient." >&2
  echo "[qa-evidence] Expected evidence: screenshot, browser interaction, page.*, locator, expect(page..." >&2
  exit 1
fi

# Silent on success
exit 0
