. "$(dirname "$0")/lib.sh"
new_repo
R="$SCRIPTS/run.sh"
echo dirty > src/dirty.sh
expect 64 "start refuses a dirty tree"           "$R" start default "t"; has "not clean"
rm src/dirty.sh
sed -i.bak 's/\$1 + \$2/0/' src/math.sh && rm src/math.sh.bak && git commit -qam broken
expect 64 "start refuses a red baseline"         "$R" start default "t"; has "baseline"
git revert --no-edit HEAD >/dev/null
expect 64 "unknown pattern rejected"             "$R" start magic "t"
expect 0 "start ok"                              "$R" start default "t"; RUN="$OUT"
expect 0 "on run branch"                         test "$(git rev-parse --abbrev-ref HEAD)" = "autopilot/$RUN"
expect 0 "current is the run"                    "$R" current; has "$RUN"
expect 64 "only one active run"                  "$R" start small "t2"; has "still active"
expect 0 "phase set"                             "$R" phase "$RUN" final
expect 0 "phase stored"                          "$R" get "$RUN" phase; has final
expect 64 "unknown phase rejected"               "$R" phase "$RUN" vibing
expect 0 "end"                                   "$R" end "$RUN" done
expect 1 "no current after end"                  "$R" current
rm -f .claude/checks.sh; git commit -qam "rm checks"
expect 64 "start requires checks.sh"             "$R" start default "t"; has "/autopilot:init"
# The repo may itself be a linked worktree of a clone whose main checkout is on another
# branch without autopilot. The run belongs to the worktree it was started in.
new_repo; MAIN="$REPO"; W="$TMP_ROOT/linked-wt"
git worktree add -q -b feature "$W"
git rm -q .autopilot/config.json && git commit -qm "main checkout: no autopilot"
cd "$W"
expect 0 "start in a linked worktree"            "$R" start small "t"; RUN="$OUT"
expect 0 "worktree is on the run branch"         test "$(git rev-parse --abbrev-ref HEAD)" = "autopilot/$RUN"
expect 0 "main checkout left on main"            test "$(git -C "$MAIN" rev-parse --abbrev-ref HEAD)" = main
expect 0 "run dir is in the worktree"            test -f "$W/.autopilot/runs/$RUN/state.json"
expect 1 "nothing written to the main checkout"  test -e "$MAIN/.autopilot/runs"
expect 0 "end in the worktree"                   "$R" end "$RUN" aborted
finish
