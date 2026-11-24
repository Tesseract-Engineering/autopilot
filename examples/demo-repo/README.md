# demo-repo

A tiny Python package for dogfooding autopilot. It already carries the per-repo
contract that `/autopilot:init` creates (`.claude/checks.sh`,
`.autopilot/config.json`, `AGENTS.md`, `CLAUDE.md`).

Make a scratch git repo from it (never work inside this folder):

    ../setup-demo.sh /tmp/autopilot-demo
    cd /tmp/autopilot-demo
    claude --plugin-dir /path/to/autopilot/plugins/autopilot

Then try `/autopilot:run` with `tasks/01-default.md` or `tasks/02-fanout.md`.
