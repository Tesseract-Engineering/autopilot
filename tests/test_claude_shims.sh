# Claude adapter shims, fed synthetic hook input (fields per the hooks reference).
. "$(dirname "$0")/lib.sh"
SHIMS="$(cd "$(dirname "$0")/../plugins/autopilot/scripts/claude" && pwd)"
export AP_CORE="$SCRIPTS"
hook() { # hook SHIM JSON
  local shim="$1" json="$2"
  printf '%s' "$json" | "$SHIMS/$shim"
}
stop_in() { jq -nc --arg c "$1" '{hook_event_name:"Stop",cwd:$c,stop_hook_active:false}'; }
sub_in() { jq -nc --arg c "$1" --arg t "$2" --arg p "$3" '{hook_event_name:"SubagentStop",cwd:$c,agent_id:"a1",agent_type:$t,agent_transcript_path:$p}'; }
pre_in() { jq -nc --arg c "$1" --arg t "$2" --arg f "$3" '{hook_event_name:"PreToolUse",cwd:$c,tool_name:"Edit",tool_input:{file_path:$f}} + (if $t=="" then {} else {agent_type:$t, agent_id:"a1"} end)'; }

# --- never gate ordinary sessions
OUTSIDE="$(mktemp -d "$TMP_ROOT/plain.XXXXXX")"
expect 0 "Stop outside a git repo: allow"            hook stop.sh "$(stop_in "$OUTSIDE")"
new_repo
expect 0 "Stop with no active run: allow"            hook stop.sh "$(stop_in "$REPO")"
sed -i.bak 's/\$1 + \$2/0/' src/math.sh && rm src/math.sh.bak
expect 0 "broken code but no run: still allow"       hook stop.sh "$(stop_in "$REPO")"
expect 0 "PreToolUse on tests with no run: allow"   hook pretooluse.sh "$(pre_in "$REPO" implementer "$REPO/tests/test_add.sh")"
git checkout -q src/math.sh

# --- small pattern: main session can't end its turn with failing tests
start_run small '{"slices":[{"id":"main","goal":"g","allowed_files":["src/math.sh"]}]}'
expect 0 "phase plan: Stop not gated"                hook stop.sh "$(stop_in "$REPO")"
"$SCRIPTS/run.sh" phase "$RUN" implement >/dev/null
sed -i.bak 's/\$1 + \$2/0/' src/math.sh && rm src/math.sh.bak
expect 2 "(a) small/implement + failing test: Stop BLOCKED (exit 2)" hook stop.sh "$(stop_in "$REPO")"
has "VERDICT: FAIL (checks)"; has "add 1 2 != 3"; has "ATTEMPT: 1/3"
git checkout -q src/math.sh
expect 0 "fixed: Stop allowed"                       hook stop.sh "$(stop_in "$REPO")"

# --- (d) escalation ends the loop cleanly
"$SCRIPTS/attempts.sh" reset "$RUN" integration
sed -i.bak 's/\$1 + \$2/0/' src/math.sh && rm src/math.sh.bak
expect 2 "fail 1 blocks"                             hook stop.sh "$(stop_in "$REPO")"
expect 2 "fail 2 blocks"                             hook stop.sh "$(stop_in "$REPO")"
expect 0 "(d) fail 3 escalates: stop ALLOWED"         hook stop.sh "$(stop_in "$REPO")"; has '"systemMessage"'; has "escalated"
expect 0 "stays allowed, no 4th attempt"             hook stop.sh "$(stop_in "$REPO")"
expect 0 "attempts capped at 3"                      "$SCRIPTS/attempts.sh" count "$RUN" integration; has 3
git checkout -q src/math.sh
"$SCRIPTS/run.sh" end "$RUN" aborted >/dev/null

# --- default pattern: SubagentStop gates by role + slice marker
new_repo; start_run default '{"slices":[{"id":"s1","goal":"g","allowed_files":["src/math.sh"]}]}'
"$SCRIPTS/run.sh" phase "$RUN" implement >/dev/null
T="$TMP_ROOT/agent.jsonl"
jq -nc --arg m "AUTOPILOT_SLICE: $RUN/s1
Implement slice s1" '{type:"user",message:{role:"user",content:$m}}' > "$T"
expect 0 "default/implement: main Stop not gated"    hook stop.sh "$(stop_in "$REPO")"
sed -i.bak 's/\$1 + \$2/0/' src/math.sh && rm src/math.sh.bak
expect 2 "(a) implementer stop with failing test: BLOCKED" hook subagent-stop.sh "$(sub_in "$REPO" autopilot:implementer "$T")"; has "UNIT: $RUN/s1"
expect 0 "other agent types are never gated"         hook subagent-stop.sh "$(sub_in "$REPO" Explore "$T")"
expect 0 "reviewer stop is not gated"                hook subagent-stop.sh "$(sub_in "$REPO" autopilot:reviewer "$T")"
git checkout -q src/math.sh
echo '# x' >> src/greet.sh
expect 2 "(b) out-of-scope edit: implementer BLOCKED" hook subagent-stop.sh "$(sub_in "$REPO" autopilot:implementer "$T")"; has "FAIL (scope)"; has "src/greet.sh"
git checkout -q src/greet.sh
"$SCRIPTS/attempts.sh" reset "$RUN" s1
echo '# weaken' >> tests/test_add.sh
expect 2 "(b) test edit via Bash: implementer BLOCKED" hook subagent-stop.sh "$(sub_in "$REPO" autopilot:implementer "$T")"; has "FAIL (tests-changed)"
git checkout -q tests/test_add.sh
"$SCRIPTS/attempts.sh" reset "$RUN" s1
expect 0 "clean slice: implementer may stop"         hook subagent-stop.sh "$(sub_in "$REPO" autopilot:implementer "$T")"
NOMARK="$TMP_ROOT/nomark.jsonl"; echo '{"type":"user","message":{"content":"do stuff"}}' > "$NOMARK"
expect 0 "missing marker: allowed with warning (no loop)" hook subagent-stop.sh "$(sub_in "$REPO" autopilot:implementer "$NOMARK")"; has "NOT gated"
# test-writer red check
jq -nc --arg m "AUTOPILOT_SLICE: $RUN/tests" '{type:"user",message:{content:$m}}' > "$T"
printf '. src/math.sh\n[ "$(mul 2 3)" = 7 ] || exit 1\n' > tests/test_mul.sh
expect 0 "test-writer with red tests may stop"       hook subagent-stop.sh "$(sub_in "$REPO" autopilot:test-writer "$T")"
printf '. src/math.sh\n[ "$(mul 2 3)" = 6 ] || exit 1\n' > tests/test_mul.sh
expect 2 "test-writer with green tests: BLOCKED"     hook subagent-stop.sh "$(sub_in "$REPO" autopilot:test-writer "$T")"; has "not-red"
rm tests/test_mul.sh

# --- PreToolUse write rules during a run
expect 2 "(b) implementer Edit on a test: DENIED"    hook pretooluse.sh "$(pre_in "$REPO" autopilot:implementer "$REPO/tests/test_add.sh")"; has "may not edit tests"
expect 0 "implementer Edit on src: allowed"          hook pretooluse.sh "$(pre_in "$REPO" autopilot:implementer "$REPO/src/math.sh")"
expect 2 "(c) reviewer Edit anywhere: DENIED"        hook pretooluse.sh "$(pre_in "$REPO" autopilot:reviewer "$REPO/src/math.sh")"; has "read-only"
expect 2 "(c) reviewer can't write run files either" hook pretooluse.sh "$(pre_in "$REPO" autopilot:reviewer "$REPO/.autopilot/runs/$RUN/x.md")"
expect 2 "main session can't touch protected paths"  hook pretooluse.sh "$(pre_in "$REPO" "" "$REPO/migrations/002.sql")"; has "protected"
expect 2 "nobody edits checks.sh during a run"       hook pretooluse.sh "$(pre_in "$REPO" "" "$REPO/.claude/checks.sh")"
expect 2 "test-writer can't write src"               hook pretooluse.sh "$(pre_in "$REPO" autopilot:test-writer "$REPO/src/math.sh")"
expect 0 "test-writer can write tests"               hook pretooluse.sh "$(pre_in "$REPO" autopilot:test-writer "$REPO/tests/test_new.sh")"
expect 2 "planner can't write src"                   hook pretooluse.sh "$(pre_in "$REPO" autopilot:planner "$REPO/src/math.sh")"
expect 0 "planner writes the plan in the run dir"    hook pretooluse.sh "$(pre_in "$REPO" autopilot:planner "$REPO/.autopilot/runs/$RUN/plan.md")"
expect 0 "main session edits src"                    hook pretooluse.sh "$(pre_in "$REPO" "" "$REPO/src/math.sh")"
# worktree paths resolve relative to the worktree root
"$SCRIPTS/worktree.sh" "$RUN" s1 >/dev/null 2>&1; WT="$(cat .autopilot/runs/$RUN/slices/s1/worktree)"
expect 2 "implementer test edit inside a worktree: DENIED" hook pretooluse.sh "$(pre_in "$WT" autopilot:implementer "$WT/tests/test_add.sh")"

# --- crash fails closed
printf '{"slices":' > ".autopilot/runs/$RUN/slices.json"   # corrupt plan -> gate errors
"$SCRIPTS/run.sh" phase "$RUN" final >/dev/null
expect 2 "gate crash fails closed (blocks)"          hook stop.sh "$(stop_in "$REPO")"
finish
