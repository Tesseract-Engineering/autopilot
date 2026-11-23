. "$(dirname "$0")/lib.sh"
new_repo; start_run default '{"slices":[{"id":"a","goal":"g","allowed_files":["src/math.sh"]},{"id":"b","goal":"g","allowed_files":["src/greet.sh"]}]}'
SC="$SCRIPTS/scope-check.sh"
expect 0 "no changes is in scope"                 "$SC" "$RUN" a
echo '# edit' >> src/math.sh
expect 0 "edit to allowed file passes"            "$SC" "$RUN" a
expect 1 "same edit is out of scope for slice b"  "$SC" "$RUN" b; has "src/math.sh"; has "outside"
expect 0 "integration scope = union of slices"    "$SC" "$RUN" integration
echo 'x' > src/new.sh
expect 1 "untracked new file outside scope fails" "$SC" "$RUN" a; has "src/new.sh"
rm src/new.sh
git add -A && git commit -q -m wip
expect 0 "committed in-scope change still passes" "$SC" "$RUN" a
echo '-- x' >> migrations/001.sql
expect 1 "protected path fails"                   "$SC" "$RUN" integration; has "protected paths changed"; has "migrations/001.sql"
git checkout -q migrations/001.sql
git rm -q src/greet.sh
expect 1 "deleting an out-of-scope file fails"    "$SC" "$RUN" a; has "src/greet.sh"
git checkout -q HEAD -- src/greet.sh
mkdir -p .autopilot/runs/"$RUN"/x .autopilot/worktrees/w && echo z > .autopilot/worktrees/w/f
expect 0 "run dirs and worktrees are ignored"     "$SC" "$RUN" a
# glob semantics
printf '{"slices":[{"id":"a","goal":"g","allowed_files":["src/*.sh"]}]}\n' > .autopilot/runs/$RUN/slices.json
mkdir -p src/deep && echo x > src/deep/x.sh
expect 1 "'*' does not cross directories"         "$SC" "$RUN" a; has "src/deep/x.sh"
printf '{"slices":[{"id":"a","goal":"g","allowed_files":["src/**"]}]}\n' > .autopilot/runs/$RUN/slices.json
expect 0 "'**' crosses directories"               "$SC" "$RUN" a
finish
