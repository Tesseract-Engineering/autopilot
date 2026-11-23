#!/usr/bin/env bash
# tests-unchanged.sh RUN [TREE]: pass (0) iff test files match the snapshot exactly
# (no edits, additions or deletions). Fail (1) lists the differences.
set -euo pipefail
. "$(dirname "$0")/lib/common.sh"
[ $# -ge 1 ] || ap_die "usage: tests-unchanged.sh RUN [TREE]"
run="$1"; need_run "$run"
snap="$(run_dir "$run")/tests.sha256"
[ -f "$snap" ] || { echo "no test snapshot for run $run" >&2; exit 1; }
now="$(hash_tests "${2:-$AP_MAIN}")"
if [ "$now" = "$(cat "$snap")" ]; then echo "tests unchanged"; exit 0; fi
echo "test files differ from the snapshot taken after the test-writer:"
diff <(cat "$snap") <(printf '%s\n' "$now" | sed '/^$/d') \
  | awk '/^[<>]/ { split($0,a,"  "); p=a[2]; s[p]=s[p] substr($0,1,1) }
         END { for (p in s) print "  " (s[p]=="<>"||s[p]=="><" ? "modified" : s[p]=="<" ? "deleted " : "added   ") "  " p }' | sort
exit 1
