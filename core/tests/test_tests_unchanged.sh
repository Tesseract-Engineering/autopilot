. "$(dirname "$0")/lib.sh"
new_repo; start_run default '{"slices":[{"id":"a","goal":"g","allowed_files":["src/math.sh"]}]}'
TU="$SCRIPTS/tests-unchanged.sh"
expect 0 "fresh snapshot matches"           "$TU" "$RUN"; has "tests unchanged"
echo '# tweak' >> tests/test_add.sh
expect 1 "modified test detected"           "$TU" "$RUN"; has "modified"; has "tests/test_add.sh"
git checkout -q tests/test_add.sh
expect 0 "restored test matches again"      "$TU" "$RUN"
echo 'exit 0' > tests/test_new.sh
expect 1 "added test file detected"         "$TU" "$RUN"; has "added"; has "tests/test_new.sh"
rm tests/test_new.sh
rm tests/test_add.sh
expect 1 "deleted test file detected"       "$TU" "$RUN"; has "deleted"; has "tests/test_add.sh"
git checkout -q tests/test_add.sh
echo '# non-test edit' >> src/math.sh
expect 0 "non-test edits don't matter"      "$TU" "$RUN"
# snapshot after test-writer: new tests become the baseline
printf '. src/math.sh\n[ "$(mul 2 3)" = 6 ] || exit 1\n' > tests/test_mul.sh
git checkout -q src/math.sh
expect 0 "tests-done commits + re-snapshots" "$SCRIPTS/run.sh" tests-done "$RUN"; has "snapshot: 2 test files"
expect 0 "new baseline matches"             "$TU" "$RUN"
expect 0 "impl_base moved to the tests commit" test "$(git rev-parse HEAD)" = "$("$SCRIPTS/run.sh" get "$RUN" impl_base)"
finish
