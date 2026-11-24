# autopilot

Run coding agents without babysitting them. **Programs decide pass/fail, never models.**

autopilot is a Claude Code plugin. It replaces "one huge prompt plus a human watching
every step" with a small graph: a planner, a test-writer that never sees the code, an
implementer that loops against a deterministic gate, and a fresh-context reviewer that
can't edit files and whose findings count only if a repro test fails. You approve the
final diff, and that's the only step you're needed for.

## Install

```
/plugin marketplace add Tesseract-Engineering/autopilot
/plugin install autopilot@autopilot
```

Requires `bash`, `git`, `jq` and `python3` (stdlib only).

## Use

```
/autopilot:init                       # once per repo: creates the contract below
/autopilot:run "add bulk pricing: 10% off when qty >= 10"
/autopilot:run tasks/fix-rounding.md  # a task file works too
```

`run` picks the cheapest pattern that has a real gate and tells you which one:

| Pattern | When | Shape |
|---|---|---|
| small | obvious change in 1–2 files | you + Stop-hook gate |
| default | new behavior | planner → (you approve the plan) → test-writer → implementer ⟲ gate → reviewer → you |
| fan-out | file-disjoint parts | planner → tests → N implementers in worktrees ⟲ gate → deterministic merge → integration gate → reviewer → you |
| best-of-n | unclear approach | 3 independent attempts → gate → pick (passes, then smallest diff) → you |
| bug-fix | broken behavior | failing repro test first (no repro: stop and ask) → fix ⟲ gate → you |

Everything happens on a branch, `autopilot/<run>`. Nothing is pushed. At the end you
get a summary with gate evidence, the kept and discarded review findings, and proposed
`AGENTS.md` rules. Those rules are proposed only, never written automatically.

## The per-repo contract

`/autopilot:init` creates the following. Review the files, then commit them.

| File | Purpose |
|---|---|
| `.claude/checks.sh` | **The** definition of "works": tests, typecheck, lint. Exit 0 = pass. The plugin only ever calls this script. |
| `.autopilot/config.json` | `test_globs`, `protected_paths`, `max_attempts` (3), `require_plan_approval` (true), `test_cmd`, `repro_cmd` (`{test}` = file), `repro_fail_codes` (the exit codes that mean "a test failed", e.g. pytest `1`) |
| `AGENTS.md` | Repo rules for every harness, in a managed block |
| `CLAUDE.md` | Imports `@AGENTS.md` |
| `.gitignore` | `.autopilot/runs/` and `.autopilot/worktrees/` |

Optional: `.worktreeinclude` (gitignored files such as `.env` to copy into worktrees) and
`.autopilot/setup.sh` (installs dependencies in a fresh worktree, for the fan-out and
best-of-n patterns).

`.autopilot/runs/<id>/` (gitignored) is each run's external memory: `state.json`,
`plan.md`, `slices.json`, frozen `config.json`, test hashes, attempt counters, gate logs,
findings and `summary.md`.

## What is enforced (and what isn't)

Hooks are **inert unless a run is active**, so ordinary sessions are never gated.
During a run:

| Rule | Enforced by |
|---|---|
| An implementer can't finish with failing checks | `SubagentStop` → `gate.sh` (exit 2 blocks) |
| The main session can't finish a small or final phase with failing checks | `Stop` → `gate.sh` |
| Tests can't change after the test-writer | `PreToolUse` deny, plus a hash check in the gate (catches writes made through Bash) |
| Only the slice's `allowed_files` may change | `gate.sh` scope check |
| `protected_paths`, `checks.sh`, `config.json` and settings are never edited | `PreToolUse` deny + gate. Config is frozen per run |
| The reviewer can't edit | agent `tools: Read, Grep, Glob` + `PreToolUse` deny |
| 3 failed attempts escalate to you instead of looping | `attempts.sh` (stops before Claude's 8-block Stop cap) |
| A finding without a failing repro is discarded | `verify-finding.sh` |
| The test-writer's tests must fail first, by assertion | `SubagentStop` → `red-check.sh` |

Everything else (routing, "don't refactor", "skip style") is guidance in the skill and
the role prompts. Only rules with zero exceptions are hooks.

**Backstop outside Claude Code** (a plain terminal, another editor):
`autopilot install-git --ci` installs `.autopilot/repo-gate.sh`, a pre-push hook and
a CI workflow that run the same checks, and refuse protected-path changes on
`autopilot/*` branches.

## When NOT to use it

- Questions, exploration, design discussions, spikes. Just chat.
- Changes with no deterministic check (copy, visual polish). A gate that can't fail
  proves nothing.
- Work you want to pair on step by step.
- Anything where about 15× the tokens of a chat isn't worth it. Multi-agent runs are
  expensive, and most coding needs shared context. That's why `small` is the default
  and fan-out requires file-disjoint slices.

## Repo layout

```
.claude-plugin/marketplace.json   marketplace entry -> plugins/autopilot
plugins/autopilot/                the plugin (the only thing that gets installed)
  .claude-plugin/plugin.json
  agents/        planner, test-writer, implementer, reviewer
  skills/        autopilot (playbook), run, init
  hooks/         hooks.json -> scripts/claude/*.sh
  scripts/       gate.sh, scope-check.sh, tests-unchanged.sh, attempts.sh, red-check.sh,
                 plan-check.sh, run.sh, worktree.sh, merge.sh, pick.sh, verify-finding.sh,
                 init.sh, repo-gate.sh, install-git.sh  (bash + jq; python3 for globs)
  scripts/claude/  hook shims: parse hook JSON, call the scripts, exit 2 to block
  bin/autopilot  single CLI over the scripts (on Claude's Bash PATH)
  git/           pre-push + CI workflow templates for install-git
tests/           plain-bash tests for the scripts and hook shims (run in CI)
examples/        demo-repo + setup-demo.sh
docs/            DESIGN.md, DOGFOOD.md
```

## Develop

```
tests/run.sh                # script tests
claude plugin validate .    # marketplace + plugin manifests
claude --plugin-dir ./plugins/autopilot   # try it locally
```
