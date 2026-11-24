#!/usr/bin/env bash
# worktree.sh RUN SLICE: create .autopilot/worktrees/<run>/<slice> on branch
# autopilot/<run>--<slice>, from the run's impl_base (which already holds the run's
# tests; NOT the default branch, unlike Claude's isolation: worktree).
# Copies gitignored files listed in .worktreeinclude, then runs .autopilot/setup.sh.
# Prints the worktree path.
set -euo pipefail
. "$(dirname "$0")/lib/common.sh"
[ $# -eq 2 ] || ap_die "usage: worktree.sh RUN SLICE"
run="$1"; slice="$2"; need_run "$run"
base="$(state_get "$run" impl_base)"
wt="$AP_MAIN/.autopilot/worktrees/$run/$slice"
d="$(slice_dir "$run" "$slice")"; mkdir -p "$d"
[ -e "$wt" ] && ap_die "worktree exists: $wt"
git -C "$AP_MAIN" worktree add -q -b "autopilot/$run--$slice" "$wt" "$base" >&2

if [ -f "$AP_MAIN/.worktreeinclude" ]; then
  ( cd "$AP_MAIN"
    git ls-files --others --ignored --exclude-from=.worktreeinclude \
      | git check-ignore --stdin \
      | ap_drop_bookkeeping \
      | while IFS= read -r f; do mkdir -p "$wt/$(dirname "$f")"; cp -p "$f" "$wt/$f"; done ) || true
fi
if [ -f "$wt/.autopilot/setup.sh" ]; then
  ( cd "$wt" && bash .autopilot/setup.sh ) >&2 || { echo "setup.sh failed in $wt" >&2; exit 1; }
fi
echo "$wt" > "$d/worktree"
echo "$wt"
