#!/usr/bin/env bash
# merge.sh RUN [SLICE...]: deterministic merge of passed slices into the run branch
# (main checkout), in slices.json order (or the order given). Uncommitted work in a
# slice worktree is committed first. Any conflict: abort, exit 1. Slices were
# supposed to be file-disjoint, so a conflict means the plan is wrong.
set -euo pipefail
. "$(dirname "$0")/lib/common.sh"
S="$(dirname "$0")"
[ $# -ge 1 ] || ap_die "usage: merge.sh RUN [SLICE...]"
run="$1"; shift; need_run "$run"
slices="$*"
[ -n "$slices" ] || slices="$(jq -r '.slices[].id' "$(run_dir "$run")/slices.json" | oneline)"
[ "$(git -C "$AP_MAIN" rev-parse --abbrev-ref HEAD)" = "$(state_get "$run" branch)" ] \
  || { echo "main checkout is not on $(state_get "$run" branch)" >&2; exit 1; }
for s in $slices; do
  st="$("$S/attempts.sh" status "$run" "$s")"
  [ "$st" = passed ] || { echo "slice $s is $st, not passed; refusing to merge" >&2; exit 1; }
  wt="$(slice_tree "$run" "$s")"
  if [ "$wt" != "$AP_MAIN" ]; then
    git -C "$wt" add -A
    git -C "$wt" diff --cached --quiet || git -C "$wt" commit -q -m "autopilot($run): slice $s"
  fi
  if ! git -C "$AP_MAIN" merge -q --no-ff --no-edit -m "autopilot($run): merge slice $s" "autopilot/$run--$s" >/dev/null 2>&1; then
    git -C "$AP_MAIN" merge --abort 2>/dev/null || true
    echo "merge conflict on slice $s; slices were not disjoint. Escalate." >&2
    exit 1
  fi
  echo "merged $s"
done
