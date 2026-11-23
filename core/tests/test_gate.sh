. "$(dirname "$0")/lib.sh"
new_repo; start_run default '{"slices":[{"id":"a","goal":"g","allowed_files":["src/math.sh"]}]}'
G="$SCRIPTS/gate.sh"
# (a) failing tests cannot pass the gate
sed -i.bak 's/\$1 + \$2/$1 - $2/' src/math.sh && rm src/math.sh.bak
expect 1 "broken code fails the gate (attempt 1)" "$G" "$RUN" a
has "UNIT: $RUN/a  ATTEMPT: 1/3"; has "VERDICT: FAIL (checks)"; has "EVIDENCE: \$ .claude/checks.sh"
has "add 1 2 != 3"; has "SCOPE: fix only: src/math.sh"
expect 0 "gate log written" test -f ".autopilot/runs/$RUN/slices/a/gate-1.log"
git checkout -q src/math.sh
expect 0 "fixed code passes"                      "$G" "$RUN" a; has "PASS"
# (b) editing a test blocks, even with checks green
"$SCRIPTS/attempts.sh" reset "$RUN" a
echo '# weaken' >> tests/test_add.sh
expect 1 "editing a test fails (tests-changed)"   "$G" "$RUN" a; has "VERDICT: FAIL (tests-changed)"; has "tests/test_add.sh"
git checkout -q tests/test_add.sh
# (b) out-of-scope file blocks
"$SCRIPTS/attempts.sh" reset "$RUN" a
echo '# x' >> src/greet.sh
expect 1 "out-of-scope edit fails (scope)"        "$G" "$RUN" a; has "VERDICT: FAIL (scope)"; has "src/greet.sh"
git checkout -q src/greet.sh
# (d) third failure escalates instead of looping
"$SCRIPTS/attempts.sh" reset "$RUN" a
echo 'exit 1' > tests/test_add.sh.tmp; sed -i.bak 's/\$1 + \$2/0/' src/math.sh && rm src/math.sh.bak
expect 1 "attempt 1 blocks"   "$G" "$RUN" a; has "ATTEMPT: 1/3"; lacks "ESCALATE"
expect 1 "attempt 2 blocks"   "$G" "$RUN" a; has "ATTEMPT: 2/3"
expect 3 "attempt 3 escalates (exit 3: let it stop)" "$G" "$RUN" a; has "ATTEMPT: 3/3"; has "ESCALATE"
expect 3 "further gate calls stay escalated, no 4th attempt" "$G" "$RUN" a; has "already used 3/3"
expect 0 "counter did not pass the cap" "$SCRIPTS/attempts.sh" count "$RUN" a; has 3
rm -f tests/test_add.sh.tmp; git checkout -q src/math.sh
# slice check runs before repo checks
new_repo; start_run default '{"slices":[{"id":"a","goal":"g","allowed_files":["src/math.sh"],"check":"grep -q mul src/math.sh && false"}]}'
expect 1 "failing slice check fails the gate"     "$G" "$RUN" a; has "VERDICT: FAIL (check)"
# missing checks.sh
new_repo; start_run default '{"slices":[{"id":"a","goal":"g","allowed_files":["src/math.sh"]}]}'
echo 'exit 0' > .claude/checks.sh
expect 1 "agent editing checks.sh is blocked"     "$G" "$RUN" a; has "protected paths changed"; has ".claude/checks.sh"
git checkout -q .claude/checks.sh
"$SCRIPTS/attempts.sh" reset "$RUN" a
echo '{"test_globs":[],"protected_paths":[]}' > .autopilot/config.json
expect 1 "agent loosening config.json is blocked" "$G" "$RUN" a; has ".autopilot/config.json"
git checkout -q .autopilot/config.json
expect 0 "gate read the frozen config, not the edited one" grep -q "VERDICT: FAIL (scope)" <<<"$OUT"
finish
