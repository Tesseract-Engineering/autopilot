#!/usr/bin/env bash
# red-check.sh RUN
# Verdict for the test-writer (unit "tests"), in the main checkout:
#   changed files since the run base are non-empty and all match test_globs, and
#   test_cmd exits with one of repro_fail_codes (tests fail for the right reason).
# Exit 0 = pass, 1 = fail, 3 = escalated.
set -uo pipefail
. "$(dirname "$0")/lib/common.sh"
[ $# -eq 1 ] || ap_die "usage: red-check.sh RUN"
run="$1"; need_run "$run"
S="$(dirname "$0")"; max="$(cfg max_attempts 3)"
base="$(state_get "$run" base)"
test_cmd="$(cfg test_cmd ./.claude/checks.sh)"
codes="$(cfg repro_fail_codes 1)"

"$S/attempts.sh" check "$run" tests || { echo "ESCALATE: $run/tests used $max/$max attempts; a human must look at the spec." >&2; exit 3; }

fail() {
  local n; n="$("$S/attempts.sh" incr "$run" tests)"
  {
    echo "UNIT: $run/tests  ATTEMPT: $n/$max"
    echo "VERDICT: FAIL ($1)"
    echo "REASON: $2"
    [ -n "${3:-}" ] && printf '%s\n' "$3" | trim_output | sed 's/^/  /'
    echo "SCOPE: write only files matching: $(cfg_list test_globs | paste -sd' ' -)"
    [ "$n" -ge "$max" ] && echo "ESCALATE: attempt cap reached ($max). Stop now and report."
  } >&2
  [ "$n" -ge "$max" ] && exit 3
  exit 1
}

changed="$(changed_files "$AP_MAIN" "$base")"
[ -n "$changed" ] || fail no-tests "no test files were written"
non_tests="$(printf '%s\n' "$changed" | ap_match out "$(cfg_list test_globs)")"
[ -z "$non_tests" ] || fail scope "test-writer changed non-test files" "$non_tests"

out="$(cd "$AP_MAIN" && bash -c "$test_cmd" 2>&1)"; code=$?
case " $codes " in
  *" $code "*) "$S/attempts.sh" pass "$run" tests
               echo "RED OK: tests fail as expected (exit $code from: $test_cmd)"; exit 0 ;;
esac
if [ "$code" -eq 0 ]; then
  fail not-red "the new tests already pass; they must fail before the change" "$out"
fi
fail wrong-failure "test command exited $code (expected one of: $codes); tests probably error instead of failing an assertion" "$out"
