#!/usr/bin/env bash
# install-git.sh [--ci]: install the harness-free backstop into this repo.
#   .autopilot/repo-gate.sh           (commit it)
#   .git/hooks/pre-push               (local, not committed)
#   .github/workflows/autopilot-gate.yml  with --ci (commit it)
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
git_adapter="$here/../git"
root="$(git rev-parse --show-toplevel)"
mkdir -p "$root/.autopilot"
cp "$here/repo-gate.sh" "$root/.autopilot/repo-gate.sh"; chmod +x "$root/.autopilot/repo-gate.sh"
echo "installed .autopilot/repo-gate.sh"
hooks="$(git rev-parse --path-format=absolute --git-path hooks)"; mkdir -p "$hooks"
if [ -e "$hooks/pre-push" ] && ! grep -q repo-gate "$hooks/pre-push"; then
  echo "kept existing $hooks/pre-push (not ours); add: .autopilot/repo-gate.sh" >&2
else
  cp "$git_adapter/pre-push" "$hooks/pre-push"; chmod +x "$hooks/pre-push"; echo "installed pre-push hook"
fi
if [ "${1:-}" = "--ci" ]; then
  mkdir -p "$root/.github/workflows"
  cp "$git_adapter/autopilot-gate.yml" "$root/.github/workflows/autopilot-gate.yml"
  echo "installed .github/workflows/autopilot-gate.yml (add toolchain setup steps)"
fi
