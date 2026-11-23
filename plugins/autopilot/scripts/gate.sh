#!/usr/bin/env bash
# gate.sh RUN UNIT [TREE]
# The verdict for one unit of work (a slice, or "integration"). In order:
#   escalated already? -> tests unchanged -> scope -> slice check -> repo checks
# Exit 0 = pass, 1 = fail (block; message on stderr), 3 = escalated (stop and hand to a human).
set -uo pipefail
. "$(dirname "$0")/lib/common.sh"
[ $# -ge 2 ] || ap_die "usage: gate.sh RUN UNIT [TREE]"
run="$1"; unit="$2"; need_run "$run"
S="$(dirname "$0")"
tree="${3:-$(slice_tree "$run" "$unit")}"
max="$(cfg max_attempts 3)"
d="$(slice_dir "$run" "$unit")"; mkdir -p "$d"

if ! "$S/attempts.sh" check "$run" "$unit"; then
  echo "ESCALATE: $run/$unit already used $max/$max attempts. Stop working on it; a human must re-plan." >&2
  exit 3
fi

allowed="$(slice_allowed "$run" "$unit" | paste -sd' ' -)"
fail() { # fail KIND REASON CMD OUTPUT
  local n log
  n="$("$S/attempts.sh" incr "$run" "$unit")"
  log="$d/gate-$n.log"
  printf 'command: %s\n\n%s\n' "$3" "$4" > "$log"
  {
    echo "UNIT: $run/$unit  ATTEMPT: $n/$max"
    echo "VERDICT: FAIL ($1)"
    echo "REASON: $2"
    echo "EVIDENCE: \$ $3"
    printf '%s\n' "$4" | trim_output | sed 's/^/  /'
    echo "SCOPE: fix only: $allowed"
    echo "LOG: $log"
    if [ "$n" -ge "$max" ]; then
      echo "ESCALATE: attempt cap reached ($max). Stop now and report; do not keep trying."
    fi
  } >&2
  [ "$n" -ge "$max" ] && exit 3
  exit 1
}

out="$("$S/tests-unchanged.sh" "$run" "$tree" 2>&1)" \
  || fail tests-changed "test files were modified; tests are fixed, change the code instead" "tests-unchanged.sh $run" "$out"

out="$("$S/scope-check.sh" "$run" "$unit" "$tree" 2>&1)" \
  || fail scope "changed files outside this unit's scope" "scope-check.sh $run $unit" "$out"

check="$(jq -r --arg s "$unit" '.slices[]? | select(.id==$s) | .check // empty' "$(run_dir "$run")/slices.json" 2>/dev/null)"
if [ -n "$check" ]; then
  out="$(cd "$tree" && bash -c "$check" 2>&1)" || fail check "slice check failed" "$check" "$out"
fi

[ -x "$tree/.claude/checks.sh" ] || fail checks "missing or non-executable .claude/checks.sh (run /autopilot:init)" ".claude/checks.sh" ""
out="$(cd "$tree" && ./.claude/checks.sh 2>&1)" || fail checks "repo checks failed" ".claude/checks.sh" "$out"

"$S/attempts.sh" pass "$run" "$unit"
echo "PASS: $run/$unit (attempt $(( $("$S/attempts.sh" count "$run" "$unit") + 1 ))/$max)"
exit 0
