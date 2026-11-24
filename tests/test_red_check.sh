. "$(dirname "$0")/lib.sh"
new_repo; start_run default '{"slices":[{"id":"a","goal":"g","allowed_files":["src/math.sh"]}]}'
R="$SCRIPTS/red-check.sh"
expect 1 "no tests written fails"                  "$R" "$RUN"; has "no-tests"
printf '. src/math.sh\n[ "$(mul 2 3)" = 6 ] || exit 1\n' > tests/test_mul.sh
expect 1 "passing new test is not red"             "$R" "$RUN"; has "not-red"
printf '. src/math.sh\n[ "$(mul 2 3)" = 7 ] || exit 1\n' > tests/test_mul.sh
echo '# x' >> src/math.sh
expect 3 "test-writer touching src fails (3rd attempt escalates)" "$R" "$RUN"; has "scope"; has "src/math.sh"; has ESCALATE
"$SCRIPTS/attempts.sh" reset "$RUN" tests
git checkout -q src/math.sh
expect 0 "red test with only test files passes"    "$R" "$RUN"; has "RED OK"
# wrong failure kind: exit code not in repro_fail_codes
printf 'exit 2\n' > tests/test_mul.sh
expect 1 "erroring (exit 2) is not a valid red"    "$R" "$RUN"; has "wrong-failure"
finish
