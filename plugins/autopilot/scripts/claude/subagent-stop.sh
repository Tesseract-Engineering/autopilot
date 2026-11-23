#!/usr/bin/env bash
# Claude SubagentStop hook. Gates autopilot:implementer (gate.sh) and
# autopilot:test-writer (red-check.sh). Other agents are never gated.
# The unit comes from the "AUTOPILOT_SLICE: <run>/<slice>" line the orchestrator
# puts first in the subagent's prompt (read from agent_transcript_path).
set -uo pipefail
. "$(dirname "$0")/_shim.sh"
agent_type="$(hin .agent_type)"
case "$agent_type" in
  autopilot:implementer|implementer) role=implementer ;;
  autopilot:test-writer|test-writer) role=test-writer ;;
  *) exit 0 ;;
esac
enter_run_or_allow
transcript="$(hin .agent_transcript_path)"
if ! unit="$(python3 "$AP_CORE/lib/ap.py" marker "$transcript" 2>/dev/null)"; then
  # Not blocking here: the subagent can't fix its own prompt, so a block would only
  # loop. The main session's final gate still runs on the merged result.
  jq -n --arg m "autopilot: $agent_type finished without an AUTOPILOT_SLICE marker; its work was NOT gated here (final gate still applies)." '{systemMessage:$m}'
  exit 0
fi
run="${unit%%/*}"; slice="${unit#*/}"
err="$(mktemp)"; trap 'rm -f "$err"' EXIT
if [ "$role" = test-writer ]; then
  "$AP_CORE/red-check.sh" "$run" >/dev/null 2>"$err"
else
  "$AP_CORE/gate.sh" "$run" "$slice" >/dev/null 2>"$err"
fi
translate $? "$err" "$unit ($role)"
