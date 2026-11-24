#!/usr/bin/env bash
# Claude Stop hook. Gates the MAIN session only while a run is active and in the
# phase where the main session owns the code: implement (small pattern) or final.
set -uo pipefail
. "$(dirname "$0")/_shim.sh"
enter_run_or_allow
phase="$("$AP_CORE/run.sh" get "$RUN" phase)"
pattern="$("$AP_CORE/run.sh" get "$RUN" pattern)"
case "$phase" in
  final) ;;
  implement) [ "$pattern" = small ] || exit 0 ;;
  *) exit 0 ;;
esac
err="$(mktemp)"; trap 'rm -f "$err"' EXIT
"$AP_CORE/gate.sh" "$RUN" integration >/dev/null 2>"$err"
translate $? "$err" "$RUN/integration"
