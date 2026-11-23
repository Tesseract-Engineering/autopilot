#!/usr/bin/env bash
# Run every core/tests/test_*.sh; exit 1 if any fails.
cd "$(dirname "$0")" || exit 1
rc=0
for t in test_*.sh; do
  echo "== $t"
  bash "$t" || rc=1
done
[ $rc -eq 0 ] && echo "ALL SCRIPT TESTS PASSED" || echo "SCRIPT TESTS FAILED"
exit $rc
