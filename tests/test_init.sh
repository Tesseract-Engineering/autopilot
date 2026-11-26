. "$(dirname "$0")/lib.sh"
AP="$(cd "$(dirname "$0")/../plugins/autopilot/bin" && pwd)/autopilot"
D="$(mktemp -d "$TMP_ROOT/init.XXXXXX")"; cd "$D"
expect 64 "init outside git fails"               "$AP" init
git init -q -b main . && git config user.email t@e && git config user.name t
printf '[project]\nname="x"\n' > pyproject.toml
printf '# Team rules\n- be nice\n' > AGENTS.md
printf '# Claude notes\n' > CLAUDE.md
expect 0 "init on a python repo"                 "$AP" init; has "(python)"; has "created  .claude/checks.sh"
expect 0 "checks.sh is executable"               test -x .claude/checks.sh
expect 0 "checks.sh runs pytest"                 grep -q "pytest" .claude/checks.sh
expect 0 "config is valid JSON w/ python globs"  jq -e '.test_globs | index("**/test_*.py")' .autopilot/config.json
expect 0 "secrets are protected by default"     jq -e '.protected_paths | index("**/.env") and index("**/secrets/**")' .autopilot/config.json
expect 0 "a nested .env matches the default"   test "$(printf 'sandbox/.env.seed
' | python3 "$SCRIPTS/lib/ap.py" match in "$(jq -r '.protected_paths[]' .autopilot/config.json)")" = sandbox/.env.seed
expect 0 "config defaults"                       jq -e '.max_attempts==3 and .require_plan_approval==true and .repro_fail_codes==[1]' .autopilot/config.json
expect 0 "gitignore has run dirs"                grep -qxF ".autopilot/runs/" .gitignore
expect 0 "existing AGENTS.md content kept"       grep -q "be nice" AGENTS.md
expect 0 "AGENTS.md got the autopilot block"     grep -q "autopilot:begin" AGENTS.md
expect 0 "CLAUDE.md imports AGENTS.md"           grep -qxF "@AGENTS.md" CLAUDE.md
expect 0 "CLAUDE.md content kept"                grep -q "Claude notes" CLAUDE.md
echo "# custom" >> .claude/checks.sh
expect 0 "re-run is idempotent"                  "$AP" init; has "kept     .claude/checks.sh"; has "kept     .autopilot/config.json"
expect 0 "custom checks.sh untouched"            grep -q "# custom" .claude/checks.sh
expect 0 "one block, one import, no dup ignores" test "$(grep -c 'autopilot:begin' AGENTS.md)$(grep -cxF '@AGENTS.md' CLAUDE.md)$(grep -cxF '.autopilot/runs/' .gitignore)" = 111
D2="$(mktemp -d "$TMP_ROOT/init.XXXXXX")"; cd "$D2"; git init -q -b main .
expect 0 "unknown stack still scaffolds"         "$AP" init; has "(unknown)"
expect 1 "unknown-stack checks.sh fails until configured" ./.claude/checks.sh
# dispatcher
expect 0 "help"                                  "$AP" help; has "verify-finding"
expect 64 "unknown command"                      "$AP" frobnicate
expect 1 "status with no run"                    "$AP" status; has "no active run"
finish
