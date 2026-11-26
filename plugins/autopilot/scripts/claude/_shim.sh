# shellcheck shell=bash
# Shared by the Claude hook shims: parse hook input, locate the core scripts.
# Shims translate core exit codes into Claude's hook protocol:
#   core 0 -> exit 0 (allow) | core 1 -> exit 2 + stderr (block; Claude sees it)
#   core 3 -> exit 0 + systemMessage (escalated: let it stop, tell the human)
#   anything else -> exit 2 "gate crashed" (fail closed)
AP_CORE="${AP_CORE:-$(cd "$(dirname "$0")/.." && pwd)}"   # plugin: scripts/claude/.. = scripts/
. "$AP_CORE/lib/platform.sh"
HOOK_INPUT="$(cat)"
# Opt-in debugging: AUTOPILOT_HOOK_LOG=/path/file records every hook input.
[ -n "${AUTOPILOT_HOOK_LOG:-}" ] && printf '%s\n' "$HOOK_INPUT" >> "$AUTOPILOT_HOOK_LOG"
hin() { printf '%s' "$HOOK_INPUT" | jq -r "$1 // empty" 2>/dev/null; }

# Only act inside a git repo that has autopilot configured and an active run.
# Ordinary sessions are never gated.
enter_run_or_allow() {
  local cwd; cwd="$(hin .cwd)"
  [ -n "$cwd" ] && cd "$cwd" 2>/dev/null || exit 0
  git rev-parse --git-dir >/dev/null 2>&1 || exit 0
  local main; main="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")"
  [ -f "$main/.autopilot/config.json" ] || exit 0
  RUN="$("$AP_CORE/run.sh" current 2>/dev/null)" || exit 0
  [ -n "$RUN" ] || exit 0
}

# translate VERDICT_EXIT ERRFILE WHAT
translate() {
  local code="$1" err="$2" what="$3"
  case "$code" in
    0) exit 0 ;;
    1) cat "$err" >&2; exit 2 ;;
    3) jq -n --arg m "autopilot: $what escalated after max attempts. $(head -c 1500 "$err")" \
         '{systemMessage: $m}'
       exit 0 ;;
    *) { echo "autopilot gate crashed (exit $code) while checking $what:"; head -40 "$err"
         echo "A human can end the run with: $AP_CORE/run.sh end $RUN aborted"; } >&2
       exit 2 ;;
  esac
}
