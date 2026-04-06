#!/bin/bash
# check-quality.sh — Stop hook: verify quality before stopping
ISSUES=()

if [ -f "tsconfig.json" ] && command -v tsc &>/dev/null; then
  if ! tsc --noEmit --quiet 2>/dev/null; then
    ISSUES+=("TypeScript compilation errors found. Run: tsc --noEmit")
  fi
fi

if [ -f "package.json" ] && command -v npm &>/dev/null; then
  if ! npm test --silent 2>/dev/null; then
    ISSUES+=("Tests are failing. Fix before stopping.")
  fi
fi

if [ ${#ISSUES[@]} -gt 0 ]; then
  echo "Quality gate failed:"
  for issue in "${ISSUES[@]}"; do echo "  - $issue"; done
fi
exit 0
