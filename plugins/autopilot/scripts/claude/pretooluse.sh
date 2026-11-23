#!/usr/bin/env bash
# Claude PreToolUse hook (Edit|Write|NotebookEdit|MultiEdit), during an active run only.
# Zero-exception write rules, by role:
#   anyone          : never protected paths (config protected_paths + the gate's inputs)
#   planner         : only .autopilot/runs/
#   test-writer     : only test_globs
#   implementer     : never test_globs
#   reviewer        : nothing at all
# Writes through Bash are not seen here; the stop gates re-check the tree.
set -uo pipefail
. "$(dirname "$0")/_shim.sh"
enter_run_or_allow
. "$AP_CORE/lib/common.sh"
need_run "$RUN"
file="$(hin '.tool_input.file_path // .tool_input.notebook_path')"
[ -n "$file" ] || exit 0
rel="$(python3 "$AP_CORE/lib/ap.py" relpath "$file")"
agent="$(hin .agent_type)"; agent="${agent#autopilot:}"
deny() { echo "autopilot: blocked write to $rel: $1" >&2; exit 2; }
is() { [ -n "$(printf '%s\n' "$rel" | ap_match in "$1")" ]; }

case "$rel" in .autopilot/runs/*)
  [ "$agent" = reviewer ] && deny "the reviewer is read-only"
  exit 0 ;;
esac
[ "$agent" = reviewer ] && deny "the reviewer is read-only; report findings with a repro test instead"
is "$(protected_patterns)" && deny "protected path (never editable by agents)"
case "$agent" in
  planner) deny "the planner writes only under .autopilot/runs/<id>/" ;;
  test-writer) is "$(cfg_list test_globs)" || deny "the test-writer may only write test files ($(cfg_list test_globs | oneline))" ;;
  implementer) is "$(cfg_list test_globs)" && deny "implementers may not edit tests; tests are the spec. Change the code." ;;
esac
exit 0
