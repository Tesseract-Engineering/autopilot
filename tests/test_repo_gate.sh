. "$(dirname "$0")/lib.sh"
AP="$(cd "$(dirname "$0")/../plugins/autopilot/bin" && pwd)/autopilot"
new_repo
expect 0 "install-git"                            "$AP" install-git --ci; has "installed pre-push hook"; has "autopilot-gate.yml"
expect 0 "pre-push hook installed"                test -x .git/hooks/pre-push
expect 0 "workflow installed"                     test -f .github/workflows/autopilot-gate.yml
git add -A && git commit -q -m "gate"
expect 0 "green main passes"                      .autopilot/repo-gate.sh HEAD
git switch -q -c feature/x
sed -i.bak 's/\$1 + \$2/0/' src/math.sh && rm src/math.sh.bak && git commit -qam break
expect 1 "failing checks fail the repo gate"      .autopilot/repo-gate.sh main; has "FAIL (checks)"
expect 1 "pre-push hook blocks the push"          .git/hooks/pre-push; has "FAIL (checks)"
git revert --no-edit HEAD >/dev/null
echo '-- human edit' >> migrations/001.sql && git commit -qam "human migration"
expect 0 "humans may change protected paths on normal branches" .autopilot/repo-gate.sh main
git switch -q main && git switch -q -c autopilot/123
echo '-- agent edit' >> migrations/001.sql && git commit -qam "agent migration"
expect 1 "agent branch touching protected path fails" .autopilot/repo-gate.sh main; has "FAIL (protected)"; has "migrations/001.sql"
git reset -q --hard HEAD~1
echo 'exit 0' > .claude/checks.sh && git commit -qam "agent neuters checks"
expect 1 "agent branch editing checks.sh fails"   .autopilot/repo-gate.sh main; has ".claude/checks.sh"
git reset -q --hard HEAD~1
echo '# ok' >> src/greet.sh && git commit -qam "normal agent change"
expect 0 "agent branch with normal change passes" .autopilot/repo-gate.sh main; has PASS
finish
