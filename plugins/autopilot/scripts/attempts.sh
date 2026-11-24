#!/usr/bin/env bash
# Per-unit attempt counter. A unit is a slice id, "tests" or "integration".
#   attempts.sh incr   RUN UNIT  -> prints new count; marks the unit escalated at max_attempts
#   attempts.sh count  RUN UNIT  -> prints count
#   attempts.sh check  RUN UNIT  -> exit 3 if escalated, else 0
#   attempts.sh status RUN UNIT  -> pending | passed | escalated
#   attempts.sh pass   RUN UNIT  -> mark passed
#   attempts.sh reset  RUN UNIT  -> count 0, pending
set -euo pipefail
. "$(dirname "$0")/lib/common.sh"
[ $# -eq 3 ] || ap_die "usage: attempts.sh incr|count|check|status|pass|reset RUN UNIT"
cmd="$1"; run="$2"; unit="$3"
need_run "$run"
d="$(slice_dir "$run" "$unit")"; mkdir -p "$d"
max="$(cfg max_attempts 3)"
count() { cat "$d/attempts" 2>/dev/null || echo 0; }
status() { cat "$d/status" 2>/dev/null || echo pending; }
case "$cmd" in
  incr)
    n=$(( $(count) + 1 )); echo "$n" > "$d/attempts"
    if [ "$n" -ge "$max" ]; then echo escalated > "$d/status"; fi
    echo "$n" ;;
  count)  count ;;
  check)  [ "$(status)" = escalated ] && exit 3; exit 0 ;;
  status) status ;;
  pass)   echo passed > "$d/status" ;;
  reset)  echo 0 > "$d/attempts"; echo pending > "$d/status" ;;
  *) ap_die "unknown command: $cmd" ;;
esac
