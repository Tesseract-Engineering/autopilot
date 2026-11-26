# Using autopilot on the sandbox repos

The sandbox is mostly generated content, so the most useful gate is not "the unit tests pass"
but **"the companies still come out exactly the same"**. The recipe below makes any change to
the generator or the emulator fail its checks, unless a human accepts the new output.

## swarm-sandbox (`sandbox/generator`)

Set up on branch `ishan-sandbox-env` of swarm-beta (2026-11-26). `generate.py` needs no model and is
deterministic, so the accepted output of every company, as hashes, is a complete regression test.

- `sandbox/generator/golden.py check` regenerates `tesseract`, `tesseract-haiku` and `harborline`, then
  compares 12 files with `golden.sha256`. It exits 1 on any difference. `golden.py write` records new
  output as accepted, and a human runs it after reading the change. Line endings are ignored:
  `write_text` gives CRLF on Windows and LF elsewhere, so plain `sha256sum` hashes would differ between
  teammates.
- `.claude/checks.sh` runs the generator's tests (when `sandbox/generator/tests/` exists), then
  `golden.py check`. It is offline and takes about 3 s. It picks a Python that has what it needs:
  `SANDBOX_PYTHON`, then the repo's `.venv`, then the Tesseract checkout beside it. With arguments, it
  runs only those pytest files; `repro_cmd` is `.claude/checks.sh {test}`.
- `.autopilot/config.json` protects:
  - `golden.sha256`: an agent can't accept its own change.
  - The model-written `brief.yaml`, `seeds*/`, `storylines*/`, `texts*/` and `chatter*/`: paid model
    output, and editing it by hand breaks "same inputs, same company".
  - The Backlot patch.
  - `.env` files, `secrets/` and `*.pem`.

The model stages (`design.py`, `plan.py`, `write.py`, `judge.py`) cost money and aren't deterministic,
so they aren't in `checks.sh`. Use autopilot on the code around them, and run the model stages yourself.

Two things this setup found on its first day:

- `generate.py tesseract` and `generate.py tesseract-haiku` crashed (`ZeroDivisionError` in
  `project_channels`). A channel with no `members` list was being scored for the Jira bot. Only
  `harborline` was being run, so nothing noticed.
- swarm-sandbox is a linked worktree of the `swarm-beta` clone. autopilot used to locate a repo
  through git's common dir, so it read the other checkout's config and would have switched branches
  there. It now uses the current work tree (`ap_checkout_root`).

## backlot-fork

The suite runs in the `backlot-dev:fork` image. Run it serially, because the live-server Google
tests are flaky under parallel load. Skip the three tests that need `git` inside the image.

`.claude/checks.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
src="$(pwd -W 2>/dev/null || pwd)"          # Docker on Windows wants C:/... not /c/...
MSYS_NO_PATHCONV=1 docker run --rm -v "$src":/src:ro -e PYTHONDONTWRITEBYTECODE=1 -w /src \
  backlot-dev:fork python -m pytest -q -p no:cacheprovider \
  --deselect tests/test_packaging.py --deselect tests/test_skills.py
```

Protect what is measured or generated, so it can't be edited to make a test pass:

```json
{
  "test_globs": ["tests/**"],
  "protected_paths": ["backlot/fidelity/baseline/**", "docs/supported-sources.md", "**/.env", "**/.env.*"],
  "test_cmd": ".claude/checks.sh",
  "repro_cmd": "MSYS_NO_PATHCONV=1 docker run --rm -v \"$(pwd -W 2>/dev/null || pwd)\":/src:ro -w /src backlot-dev:fork python -m pytest -q -p no:cacheprovider {test}",
  "repro_fail_codes": [1]
}
```

Docker must be running, or the baseline check in `autopilot start` fails before the run begins.
That is the intended behavior.

## Which pattern for which sandbox job

| Job | Pattern |
|---|---|
| Fix a generator crash or a wrong record | `bug-fix`: the repro is a failing test, or a company that no longer regenerates |
| A new emulator endpoint (for example another Graph route) | `default`: the planner writes the spec, the test-writer writes tests from the vendor's documented behavior, without seeing the code |
| Emulate a new vendor (Teams, Exchange) | `fan-out`, with one slice per router file, when the files are disjoint |
| Accept a deliberate change in generated output | not autopilot: read the `out/` diff, regenerate `golden.sha256`, commit |
