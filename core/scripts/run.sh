#!/usr/bin/env bash
# Run lifecycle. State lives in .autopilot/runs/<id>/ (gitignored): external memory
# that survives context compaction.
#   run.sh start PATTERN "TASK"   new run: clean tree + green baseline required;
#                                 creates branch autopilot/<id>; prints <id>
#   run.sh current                prints the active run id (exit 1 if none)
#   run.sh get RUN [KEY]          state.json (or one key)
#   run.sh phase RUN PHASE        plan|plan_review|tests|implement|review|final
#   run.sh tests-done RUN         commit test-writer output, set impl_base, snapshot tests
#   run.sh commit RUN MESSAGE     commit everything on the run branch (main checkout)
#   run.sh status RUN             state + per-unit attempts/status
#   run.sh end RUN done|aborted|escalated   finish: clear current, remove worktrees
# PATTERN: small | default | fan-out | best-of-n | bug-fix
set -euo pipefail
. "$(dirname "$0")/lib/common.sh"
S="$(dirname "$0")"
cmd="${1:-}"; shift || true

commit_all() { # commit_all MESSAGE: no-op if clean
  git -C "$AP_MAIN" add -A
  git -C "$AP_MAIN" diff --cached --quiet || git -C "$AP_MAIN" commit -q -m "$1"
}

case "$cmd" in
  start)
    [ $# -eq 2 ] || ap_die "usage: run.sh start PATTERN \"TASK\""
    pattern="$1"; task="$2"
    case "$pattern" in small|default|fan-out|best-of-n|bug-fix) ;; *) ap_die "unknown pattern: $pattern" ;; esac
    [ -f "$AP_CONFIG" ] || ap_die "no .autopilot/config.json; run /autopilot:init first"
    [ -x "$AP_MAIN/.claude/checks.sh" ] || ap_die "no executable .claude/checks.sh; run /autopilot:init first"
    if cur="$(current_run)" && [ -n "$cur" ]; then ap_die "run $cur is still active (run.sh end $cur aborted)"; fi
    if [ -n "$(git -C "$AP_MAIN" status --porcelain)" ]; then
      ap_die "working tree is not clean; commit or stash first so the run has a clean base"
    fi
    if ! out="$(cd "$AP_MAIN" && ./.claude/checks.sh 2>&1)"; then
      printf '%s\n' "$out" | trim_output >&2
      ap_die "baseline .claude/checks.sh fails before any change; fix that first (the gate could never pass)"
    fi
    id="$(date +%Y%m%d-%H%M%S)"
    while [ -e "$(run_dir "$id")" ]; do id="$id-x"; done
    mkdir -p "$(run_dir "$id")/slices"
    cp "$AP_CONFIG" "$(run_dir "$id")/config.json"
    printf '%s\n' "$task" > "$(run_dir "$id")/task.md"
    head="$(git -C "$AP_MAIN" rev-parse HEAD)"
    from="$(git -C "$AP_MAIN" rev-parse --abbrev-ref HEAD)"
    git -C "$AP_MAIN" switch -q -c "autopilot/$id"
    jq -n --arg id "$id" --arg p "$pattern" --arg b "autopilot/$id" --arg h "$head" --arg f "$from" \
      '{run_id:$id, pattern:$p, phase:"plan", branch:$b, from_branch:$f, base:$h, impl_base:$h}' \
      > "$(run_dir "$id")/state.json"
    echo "$id" > "$AP_RUNS/current"
    "$S/snapshot-tests.sh" "$id" >/dev/null
    echo "$id" ;;
  current) cur="$(current_run)" && [ -n "$cur" ] && echo "$cur" ;;
  get)
    need_run "$1"
    if [ $# -ge 2 ]; then state_get "$1" "$2"; else cat "$(run_dir "$1")/state.json"; fi ;;
  phase)
    [ $# -eq 2 ] || ap_die "usage: run.sh phase RUN PHASE"
    need_run "$1"
    case "$2" in plan|plan_review|tests|implement|review|final) ;; *) ap_die "unknown phase: $2" ;; esac
    state_set "$1" phase "$2"; echo "phase: $2" ;;
  tests-done)
    need_run "$1"
    commit_all "autopilot($1): failing tests from test-writer"
    state_set "$1" impl_base "$(git -C "$AP_MAIN" rev-parse HEAD)"
    "$S/snapshot-tests.sh" "$1" ;;
  commit)
    [ $# -eq 2 ] || ap_die "usage: run.sh commit RUN MESSAGE"
    need_run "$1"; commit_all "autopilot($1): $2"; git -C "$AP_MAIN" log --oneline -1 ;;
  status)
    need_run "$1"; cat "$(run_dir "$1")/state.json"
    for d in "$(run_dir "$1")"/slices/*/; do
      [ -d "$d" ] || continue
      u="$(basename "$d")"
      printf '%-14s %-10s attempts=%s\n' "$u" "$("$S/attempts.sh" status "$1" "$u")" "$("$S/attempts.sh" count "$1" "$u")"
    done ;;
  end)
    [ $# -eq 2 ] || ap_die "usage: run.sh end RUN done|aborted|escalated"
    need_run "$1"
    case "$2" in done|aborted|escalated) ;; *) ap_die "unknown end state: $2" ;; esac
    state_set "$1" phase "$2"
    for wt in "$(run_dir "$1")"/slices/*/worktree; do
      [ -f "$wt" ] || continue
      git -C "$AP_MAIN" worktree remove --force "$(cat "$wt")" 2>/dev/null || true
      rm -f "${wt:?}"
    done
    if [ "$(current_run 2>/dev/null || true)" = "$1" ]; then rm -f "${AP_RUNS:?}/current"; fi
    echo "run $1: $2 (branch $(state_get "$1" branch))" ;;
  *) ap_die "usage: run.sh start|current|get|phase|tests-done|commit|status|end ..." ;;
esac
