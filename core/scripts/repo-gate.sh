#!/usr/bin/env bash
# repo-gate.sh [BASE]: the harness-free backstop (git pre-push hook, CI).
# Standalone on purpose: it's copied into repos as .autopilot/repo-gate.sh and
# needs only bash, git and jq.
#   1. .claude/checks.sh must exit 0.
#   2. On autopilot/* branches: no file under protected_paths (or the gate's own
#      inputs) may differ from BASE.
# BASE defaults to the merge-base with origin/HEAD (or main).
set -uo pipefail
root="$(git rev-parse --show-toplevel)" || exit 64
cd "$root" || exit 64
base="${1:-}"
if [ -z "$base" ]; then
  up="$(git rev-parse --abbrev-ref origin/HEAD 2>/dev/null || echo main)"
  base="$(git merge-base HEAD "$up" 2>/dev/null || true)"
fi
[ -x .claude/checks.sh ] || { echo "repo-gate: missing executable .claude/checks.sh" >&2; exit 1; }
if ! out="$(./.claude/checks.sh 2>&1)"; then
  echo "repo-gate: FAIL (checks)  \$ .claude/checks.sh" >&2
  printf '%s\n' "$out" | tail -40 | sed 's/^/  /' >&2
  exit 1
fi
branch="${GITHUB_HEAD_REF:-$(git rev-parse --abbrev-ref HEAD)}"
case "$branch" in
  autopilot/*)
    [ -n "$base" ] || { echo "repo-gate: cannot find a base to compare protected paths" >&2; exit 1; }
    pats=".claude/checks.sh
.claude/settings.json
.claude/settings.local.json
.autopilot/config.json"
    [ -f .autopilot/config.json ] && pats="$pats
$(jq -r '.protected_paths // [] | .[]' .autopilot/config.json)"
    specs=""
    while IFS= read -r p; do [ -n "$p" ] && specs="$specs:(glob)${p%/}"$'\n'; done <<< "$pats"
    # a dir pattern like "migrations" should cover everything below it
    hits="$(printf '%s' "$specs" | while IFS= read -r s; do git diff --name-only "$base" -- "$s" "$s/**"; done | sort -u)"
    if [ -n "$hits" ]; then
      echo "repo-gate: FAIL (protected) on agent branch $branch; changed since $base:" >&2
      printf '%s\n' "$hits" | sed 's/^/  /' >&2
      exit 1
    fi ;;
esac
echo "repo-gate: PASS"
