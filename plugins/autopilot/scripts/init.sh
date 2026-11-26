#!/usr/bin/env bash
# init.sh: scaffold the per-repo contract. Idempotent: existing files are kept,
# and the AGENTS.md block between autopilot markers is refreshed.
#   .claude/checks.sh        repo checks (exit 0 = pass); stack-detected skeleton
#   .autopilot/config.json   test_globs, protected_paths, max_attempts, ...
#   .gitignore               += .autopilot/runs/ .autopilot/worktrees/
#   AGENTS.md                harness-neutral rules (marked block)
#   CLAUDE.md                imports @AGENTS.md
set -euo pipefail
root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "init: not inside a git repository" >&2; exit 64; }
cd "$root"
done_msgs=""
note() { done_msgs="$done_msgs  $1"$'\n'; }

# --- detect stack (first match wins)
if [ -f pyproject.toml ] || [ -f setup.py ] || [ -f setup.cfg ] || ls requirements*.txt >/dev/null 2>&1; then
  stack=python; test_cmd="python3 -m pytest -q -p no:cacheprovider"
  globs='["tests/**", "**/test_*.py", "**/*_test.py", "**/conftest.py"]'
  repro='python3 -m pytest -q -p no:cacheprovider {test}'; codes='[1]'
elif [ -f package.json ]; then
  stack=node; test_cmd="npm test --silent"
  globs='["test/**", "tests/**", "**/__tests__/**", "**/*.test.*", "**/*.spec.*"]'
  repro='npm test --silent -- {test}'; codes='[1]'
elif [ -f go.mod ]; then
  stack=go; test_cmd="go test ./..."
  globs='["**/*_test.go", "**/testdata/**"]'
  repro='go test ./...'; codes='[1]'
elif [ -f Cargo.toml ]; then
  stack=rust; test_cmd="cargo test --quiet"
  globs='["tests/**"]'
  repro='cargo test --quiet'; codes='[101]'
else
  stack=unknown; test_cmd='echo "autopilot: edit .claude/checks.sh to run this repo'"'"'s tests" >&2; exit 1'
  globs='["tests/**", "test/**"]'; repro='false {test}'; codes='[1]'
fi

# --- .claude/checks.sh
mkdir -p .claude
if [ -e .claude/checks.sh ]; then
  note "kept     .claude/checks.sh"
else
  cat > .claude/checks.sh <<EOF
#!/usr/bin/env bash
# Repo checks for autopilot's gate. Exit 0 = pass, anything else = fail.
# Keep it deterministic and reasonably fast; add typecheck/lint below the tests.
# Detected stack: $stack
set -euo pipefail
cd "\$(dirname "\$0")/.."
$test_cmd
EOF
  chmod +x .claude/checks.sh
  note "created  .claude/checks.sh ($stack): REVIEW IT"
fi

# --- .autopilot/config.json
mkdir -p .autopilot
if [ -e .autopilot/config.json ]; then
  note "kept     .autopilot/config.json"
else
  jq -n --argjson g "$globs" --arg t "$test_cmd" --arg r "$repro" --argjson c "$codes" '{
    test_globs: $g,
    protected_paths: ["migrations/**", "**/migrations/**", ".github/workflows/**",
                      "**/.env", "**/.env.*", "**/secrets/**"],
    max_attempts: 3,
    require_plan_approval: true,
    test_cmd: $t,
    repro_cmd: $r,
    repro_fail_codes: $c
  }' > .autopilot/config.json
  note "created  .autopilot/config.json (edit protected_paths for this repo)"
fi

# --- .gitignore
touch .gitignore
for line in ".autopilot/runs/" ".autopilot/worktrees/"; do
  grep -qxF "$line" .gitignore || { printf '%s\n' "$line" >> .gitignore; note "added    $line to .gitignore"; }
done

# --- AGENTS.md (marked block, refreshed every time)
IFS= read -r -d '' block <<'EOF' || true   # (bash 3.2: no heredoc inside $(...))
<!-- autopilot:begin (managed by autopilot init; edit outside this block) -->
## autopilot rules (all agents, all harnesses)
- `.claude/checks.sh` is the definition of "works". Run it before calling anything done.
- Files matching `test_globs` in `.autopilot/config.json` are the spec during a run.
  Implementers never edit them.
- `protected_paths` in `.autopilot/config.json`, `.claude/checks.sh` and
  `.autopilot/config.json` itself are never edited by agents.
- Reviewer findings need a failing repro test. Findings without one are discarded.
- Rules learned from autopilot runs are proposed in each run's summary and added
  below this block **by a human**.
<!-- autopilot:end -->
EOF
block="${block%$'\n'}"
if [ ! -e AGENTS.md ]; then
  printf '# Agent rules\n\n%s\n' "$block" > AGENTS.md
  note "created  AGENTS.md"
elif grep -q '<!-- autopilot:begin' AGENTS.md; then
  python3 - "$block" <<'PY'
import re, sys
p = "AGENTS.md"; s = open(p, encoding="utf-8").read()
s = re.sub(r"<!-- autopilot:begin.*?<!-- autopilot:end -->", lambda m: sys.argv[1], s, count=1, flags=re.S)
open(p, "w", encoding="utf-8", newline="\n").write(s)
PY
  note "updated  AGENTS.md autopilot block"
else
  printf '\n%s\n' "$block" >> AGENTS.md
  note "appended autopilot block to AGENTS.md"
fi

# --- CLAUDE.md imports AGENTS.md
if [ ! -e CLAUDE.md ]; then
  printf '@AGENTS.md\n' > CLAUDE.md; note "created  CLAUDE.md (@AGENTS.md)"
elif ! grep -qxF '@AGENTS.md' CLAUDE.md; then
  printf '\n@AGENTS.md\n' >> CLAUDE.md; note "added    @AGENTS.md import to CLAUDE.md"
else
  note "kept     CLAUDE.md (already imports @AGENTS.md)"
fi

printf 'autopilot init (%s):\n%s' "$stack" "$done_msgs"
echo "next: review .claude/checks.sh, run it (must exit 0 on a clean tree), then commit these files."
