#!/usr/bin/env bash
# setup-demo.sh DEST: copy examples/demo-repo into DEST as a fresh git repo.
# (The demo can't be a git repo inside this repo, so it's materialized on demand.)
set -euo pipefail
[ $# -eq 1 ] || { echo "usage: setup-demo.sh DEST" >&2; exit 64; }
src="$(cd "$(dirname "$0")/demo-repo" && pwd)"
dest="$1"
[ -e "$dest" ] && { echo "$dest already exists" >&2; exit 1; }
mkdir -p "$dest"
cp -R "$src/." "$dest/"
cd "$dest"
git init -q -b main .
git add -A
git -c user.name=autopilot-demo -c user.email=demo@example.invalid commit -q -m "demo: initial"
echo "demo repo ready: $dest"
