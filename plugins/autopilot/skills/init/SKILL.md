---
name: init
description: Set up a repository for autopilot. Creates .claude/checks.sh, .autopilot/config.json, AGENTS.md rules and the CLAUDE.md import. Use when the user types /autopilot:init.
disable-model-invocation: true
---
Set up this repository for autopilot.

1. Run `autopilot init` and show the user its output.
2. Open `.claude/checks.sh`. It is the **only** definition of "works" the gate uses.
   Look at the repo (CI config, Makefile, package scripts, pyproject) and propose the
   real check commands: tests first, then typecheck and lint if the repo uses them.
   Show the proposed script and edit it only after the user agrees. Keep it
   deterministic: no network, no flaky steps.
3. Open `.autopilot/config.json` and check, with the user:
   - `test_globs`: must match every test file in this repo and nothing else.
   - `protected_paths`: things agents must never touch (migrations, generated code,
     vendored code, CI workflows).
   - `test_cmd` / `repro_cmd` / `repro_fail_codes`: the exit code meaning "a test
     failed" (pytest 1, jest 1, cargo 101), as opposed to "the test errored".
   - `require_plan_approval` (default true).
4. Run `./.claude/checks.sh` on the clean tree. It must exit 0, or autopilot will refuse
   to start a run. Report the result.
5. Mention the optional extras: `.worktreeinclude` (gitignored files such as `.env` to
   copy into worktrees) and `.autopilot/setup.sh` (installs dependencies in a fresh
   worktree; needed for the fan-out and best-of-N patterns).
6. Don't commit. Tell the user which files to review and commit.
