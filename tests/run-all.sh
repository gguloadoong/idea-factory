#!/usr/bin/env bash
# tests/run-all.sh — idea-factory test suite runner
#
# Discovers and runs:
#   1. All tests/**/*.test.sh files
#   2. tests/invariant-exit-zero.sh (v7 regression guard, runs last)
#
# Each test file must exit 0 on success. This runner aggregates results
# and exits 0 only if every test passed.

set +e  # individual test failures should not abort the runner
cd "$(dirname "$0")/.." || exit 1

PASS=0
FAIL=0
FAILED_TESTS=()

echo "idea-factory test suite"
echo "========================"

# Hook-specific tests
while IFS= read -r test_file; do
  echo ""
  echo "▶ $test_file"
  if bash "$test_file"; then
    PASS=$((PASS + 1))
    echo "  ✓ PASS"
  else
    FAIL=$((FAIL + 1))
    FAILED_TESTS+=("$test_file")
    echo "  ✗ FAIL"
  fi
done < <(find tests -name "*.test.sh" -type f 2>/dev/null | sort)

# v7 regression guard — runs last, applies to all hooks
echo ""
echo "▶ tests/invariant-exit-zero.sh (v7 regression guard)"
if bash tests/invariant-exit-zero.sh; then
  PASS=$((PASS + 1))
  echo "  ✓ PASS"
else
  FAIL=$((FAIL + 1))
  FAILED_TESTS+=("tests/invariant-exit-zero.sh")
  echo "  ✗ FAIL"
fi

echo ""
echo "========================"
echo "Results: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "Failed tests:"
  printf '  - %s\n' "${FAILED_TESTS[@]}"
  exit 1
fi

exit 0
