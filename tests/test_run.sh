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
finish
