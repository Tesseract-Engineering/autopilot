. "$(dirname "$0")/lib.sh"
P="$SCRIPTS/plan-check.sh"
new_repo; start_run default '{"slices":[{"id":"a","goal":"g","allowed_files":["src/math.sh"]}]}'
expect 0 "valid plan"                             "$P" "$RUN"; has "1 slice(s)"
echo 'not json' > .autopilot/runs/$RUN/slices.json
expect 1 "invalid JSON"                           "$P" "$RUN"
echo '{"slices":[{"id":"A b","goal":"","allowed_files":[]}]}' > .autopilot/runs/$RUN/slices.json
expect 1 "bad id, empty goal, empty files"       "$P" "$RUN"; has "must match"; has "missing goal"; has "allowed_files is empty"
echo '{"slices":[{"id":"a","goal":"g","allowed_files":["tests/test_add.sh"]}]}' > .autopilot/runs/$RUN/slices.json
expect 1 "test paths not allowed for implementers" "$P" "$RUN"; has "test paths"
echo '{"slices":[{"id":"a","goal":"g","allowed_files":["migrations/002.sql"]}]}' > .autopilot/runs/$RUN/slices.json
expect 1 "protected paths not allowed"             "$P" "$RUN"; has "protected"
echo '{"slices":[{"id":"integration","goal":"g","allowed_files":["src/x"]}]}' > .autopilot/runs/$RUN/slices.json
expect 1 "reserved id"                             "$P" "$RUN"; has reserved
"$SCRIPTS/run.sh" end "$RUN" aborted >/dev/null
start_run fan-out '{"slices":[{"id":"a","goal":"g","allowed_files":["src/math.sh"],"check":"true"},{"id":"b","goal":"g","allowed_files":["src/greet.sh"],"check":"true"}]}'
expect 0 "disjoint fan-out ok"                     "$P" "$RUN"
echo '{"slices":[{"id":"a","goal":"g","allowed_files":["src/math.sh"],"check":"true"},{"id":"b","goal":"g","allowed_files":["./src/math.sh","src/greet.sh"],"check":"true"}]}' > .autopilot/runs/$RUN/slices.json
expect 1 "overlapping fan-out rejected"            "$P" "$RUN"; has "not file-disjoint"; has "src/math.sh"
echo '{"slices":[{"id":"a","goal":"g","allowed_files":["src/*.sh"],"check":"true"},{"id":"b","goal":"g","allowed_files":["src/greet.sh"],"check":"true"}]}' > .autopilot/runs/$RUN/slices.json
expect 1 "globs rejected in fan-out"               "$P" "$RUN"; has "literal file paths"
echo '{"slices":[{"id":"a","goal":"g","allowed_files":["src/math.sh"]},{"id":"b","goal":"g","allowed_files":["src/greet.sh"],"check":"true"}]}' > .autopilot/runs/$RUN/slices.json
expect 1 "multi-slice plan needs a check per slice" "$P" "$RUN"; has "slice a: needs a check"
finish
