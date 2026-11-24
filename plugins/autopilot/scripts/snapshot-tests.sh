#!/usr/bin/env bash
# snapshot-tests.sh RUN [TREE]: record hashes of every test file (test_globs).
set -euo pipefail
. "$(dirname "$0")/lib/common.sh"
[ $# -ge 1 ] || ap_die "usage: snapshot-tests.sh RUN [TREE]"
run="$1"; need_run "$run"
hash_tests "${2:-$AP_MAIN}" > "$(run_dir "$run")/tests.sha256"
echo "snapshot: $(wc -l < "$(run_dir "$run")/tests.sha256" | tr -d ' ') test files"
