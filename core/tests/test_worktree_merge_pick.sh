. "$(dirname "$0")/lib.sh"
new_repo
echo 'SECRET=1' > .env; echo '.env' >> .gitignore; echo '.env' > .worktreeinclude
mkdir -p .autopilot && printf 'echo setup-ran > .setup-marker\n' > .autopilot/setup.sh
echo '.setup-marker' >> .gitignore
git add -A && git commit -q -m "env"
start_run fan-out '{"slices":[{"id":"mul","goal":"g","allowed_files":["src/math.sh"]},{"id":"greet","goal":"g","allowed_files":["src/greet.sh"]}]}'
# tests from the test-writer are committed on the run branch before worktrees exist
printf '. src/math.sh\n[ "$(mul 2 3)" = 6 ] || exit 1\n' > tests/test_mul.sh
"$SCRIPTS/run.sh" tests-done "$RUN" >/dev/null
W="$SCRIPTS/worktree.sh"
expect 0 "create worktree for slice mul"        "$W" "$RUN" mul; WT_MUL="$(printf '%s\n' "$OUT" | tail -1)"
expect 0 "worktree has the run's tests (HEAD, not default branch)" test -f "$WT_MUL/tests/test_mul.sh"
expect 0 ".worktreeinclude copied .env"         test -f "$WT_MUL/.env"
expect 0 "setup.sh ran in worktree"             test -f "$WT_MUL/.setup-marker"
expect 0 "create worktree for slice greet"      "$W" "$RUN" greet; WT_GREET="$(printf '%s\n' "$OUT" | tail -1)"
expect 64 "refuses to recreate"                 "$W" "$RUN" greet
# implementers work; gate runs in each worktree
printf '# tweaked\n' >> "$WT_GREET/src/greet.sh"
expect 0 "gate passes in greet worktree"        "$SCRIPTS/gate.sh" "$RUN" greet
echo '# no-op' >> "$WT_MUL/src/greet.sh"
expect 1 "scope enforced inside worktree"       "$SCRIPTS/gate.sh" "$RUN" mul; has "src/greet.sh"
(cd "$WT_MUL" && git checkout -q src/greet.sh)
expect 0 "slice mul gate passes"                "$SCRIPTS/gate.sh" "$RUN" mul
expect 0 "deterministic merge in plan order"    "$SCRIPTS/merge.sh" "$RUN"; has "merged mul"; has "merged greet"
expect 0 "integration gate passes"              "$SCRIPTS/gate.sh" "$RUN" integration
expect 0 "merged tree has both slices"          grep -q tweaked src/greet.sh
# refuses to merge unpassed slices
new_repo; start_run fan-out '{"slices":[{"id":"a","goal":"g","allowed_files":["src/math.sh"]}]}'
"$W" "$RUN" a >/dev/null 2>&1
expect 1 "merge refuses unpassed slice"         "$SCRIPTS/merge.sh" "$RUN"; has "not passed"
# conflict -> abort
new_repo; start_run best-of-n '{"slices":[{"id":"c1","goal":"g","allowed_files":["src/math.sh"]},{"id":"c2","goal":"g","allowed_files":["src/math.sh"]},{"id":"c3","goal":"g","allowed_files":["src/math.sh"]}]}'
for c in c1 c2 c3; do "$W" "$RUN" $c >/dev/null 2>&1; done
WT1="$(cat .autopilot/runs/$RUN/slices/c1/worktree)"; WT2="$(cat .autopilot/runs/$RUN/slices/c2/worktree)"; WT3="$(cat .autopilot/runs/$RUN/slices/c3/worktree)"
printf 'add() { echo $(( $1 + $2 )); }\nmul() { r=0; i=0; while [ $i -lt $2 ]; do r=$((r+$1)); i=$((i+1)); done; echo $r; }\n# long\n# long\n' > "$WT1/src/math.sh"
printf 'add() { echo $(( $1 + $2 )); }\nmul() { echo $(( $2 * $1 )); }\n' > "$WT2/src/math.sh"
printf 'add() { echo 0; }\n' > "$WT3/src/math.sh"
for c in c1 c2 c3; do "$SCRIPTS/gate.sh" "$RUN" $c >/dev/null 2>&1; done
expect 0 "pick: smallest passing diff wins"     "$SCRIPTS/pick.sh" "$RUN"; has "c3: pending"; has "c2: passed, 2 lines"
expect 0 "winner is c2"                         test "$(printf '%s\n' "$OUT" | tail -1)" = c2
expect 1 "merging overlapping candidates conflicts -> abort" "$SCRIPTS/merge.sh" "$RUN" c2 c1; has "merge conflict on slice c1"
expect 0 "merge aborted cleanly"                test -z "$(git status --porcelain)"
expect 0 "end removes worktrees"                "$SCRIPTS/run.sh" end "$RUN" done
expect 1 "worktree gone"                        test -d "$WT1"
finish
