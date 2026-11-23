#!/usr/bin/env bash
# pick.sh RUN [SLICE...]: best-of-N selection by rule. Among candidates whose gate
# passed, pick the smallest diff (insertions + deletions vs impl_base); ties go to
# the earliest candidate. Prints the winner id; exit 1 if none passed.
set -euo pipefail
. "$(dirname "$0")/lib/common.sh"
S="$(dirname "$0")"
[ $# -ge 1 ] || ap_die "usage: pick.sh RUN [SLICE...]"
run="$1"; shift; need_run "$run"
cands="$*"
[ -n "$cands" ] || cands="$(jq -r '.slices[].id' "$(run_dir "$run")/slices.json" | oneline)"
base="$(state_get "$run" impl_base)"
best=""; best_size=""
for s in $cands; do
  st="$("$S/attempts.sh" status "$run" "$s")"
  if [ "$st" != passed ]; then echo "  $s: $st (skipped)" >&2; continue; fi
  wt="$(slice_tree "$run" "$s")"
  git -C "$wt" add -A
  git -C "$wt" diff --cached --quiet || git -C "$wt" commit -q -m "autopilot($run): candidate $s"
  size="$(git -C "$wt" diff --numstat "$base" HEAD | awk '{ a += ($1=="-"?0:$1) + ($2=="-"?0:$2) } END { print a+0 }')"
  echo "  $s: passed, $size lines changed" >&2
  if [ -z "$best" ] || [ "$size" -lt "$best_size" ]; then best="$s"; best_size="$size"; fi
done
[ -n "$best" ] || { echo "no candidate passed the gate; escalate" >&2; exit 1; }
echo "$best"
