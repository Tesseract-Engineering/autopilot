#!/usr/bin/env bash
# scope-check.sh RUN SLICE [TREE]
# Pass (0) iff every file changed since the run's impl_base is in the slice's
# allowed_files and none is under protected_paths. Fail (1) lists offenders.
set -euo pipefail
. "$(dirname "$0")/lib/common.sh"
[ $# -ge 2 ] || ap_die "usage: scope-check.sh RUN SLICE [TREE]"
run="$1"; slice="$2"; need_run "$run"
tree="${3:-$(slice_tree "$run" "$slice")}"
base="$(state_get "$run" impl_base)"
allowed="$(slice_allowed "$run" "$slice")"
[ -n "$allowed" ] || { echo "slice '$slice' has no allowed_files" >&2; exit 1; }

changed="$(changed_files "$tree" "$base")"
protected="$(printf '%s\n' "$changed" | ap_match in "$(protected_patterns)")"
outside="$(printf '%s\n' "$changed" | ap_match out "$allowed")"

if [ -n "$protected" ] || [ -n "$outside" ]; then
  [ -n "$protected" ] && { echo "protected paths changed:"; printf '%s\n' "$protected" | sed 's/^/  /'; }
  [ -n "$outside" ] && { echo "files outside the slice's allowed_files:"; printf '%s\n' "$outside" | sed 's/^/  /'; }
  echo "allowed_files: $(printf '%s\n' "$allowed" | paste -sd' ' -)"
  exit 1
fi
echo "scope ok ($(printf '%s\n' "$changed" | sed '/^$/d' | wc -l | tr -d ' ') files changed)"
