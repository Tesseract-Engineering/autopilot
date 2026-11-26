# Using autopilot on the sandbox repos

The sandbox is mostly generated content, so the most useful gate is not "the unit tests pass"
but **"the companies still come out exactly the same"**. The recipe below makes any change to
the generator or the emulator fail its checks, unless a human accepts the new output.

## swarm-sandbox (`sandbox/generator`)

`generate.py` needs no model and is deterministic. The same inputs give the same bytes, so a
committed hash manifest is a complete regression test for every company.

`.claude/checks.sh`:

```bash
#!/usr/bin/env bash
# Every company regenerates without a model and matches its accepted output.
set -euo pipefail
cd "$(dirname "$0")/../sandbox/generator"
PY="${SANDBOX_PYTHON:-../../../Tesseract/.venv/Scripts/python.exe}"   # needs pyyaml; bin/python off Windows
for c in tesseract tesseract-haiku harborline; do "$PY" generate.py "$c" >/dev/null; done
sha256sum --quiet -c golden.sha256
```

Make the manifest once, after reading the output, and commit it:

```bash
cd sandbox/generator
sha256sum out/*/corpus_all.jsonl out/*/answer_key.json out/*/roster.yaml out/*/scope.json > golden.sha256
```

`.autopilot/config.json`, with the parts that matter here:

```json
{
  "test_globs": ["sandbox/generator/tests/**"],
  "protected_paths": [
    "sandbox/generator/golden.sha256",
    "sandbox/generator/companies/*/texts/**",
    "sandbox/generator/companies/*/storylines/**",
    "sandbox/secrets/**", "**/.env", "**/.env.*", "**/secrets/**"
  ],
  "test_cmd": ".claude/checks.sh",
  "repro_fail_codes": [1]
}
```

Why these paths are protected:

- **`golden.sha256`**: an agent that changes the output must not be able to accept its own
  change. A human regenerates the manifest after reading the diff of `out/`.
- **`texts/` and `storylines/`**: these were written by a paid model run. Editing them by hand
  breaks the "everything is a file, same inputs give the same company" rule.
- **Secrets**: `sandbox/.env.seed`, `sandbox/secrets/` and the generator's `.env` hold real tokens and
  the API key. Since 0.1.1, `autopilot init` protects `.env` files and `secrets/` folders by default.

The model stages (`design.py`, `plan.py`, `write.py`, `judge.py`) cost money and aren't
deterministic, so they don't belong in `checks.sh`. Use autopilot on the code around them,
and run the model stages yourself.

Found while writing this recipe: on 2026-11-26, `generate.py tesseract` and
`generate.py tesseract-haiku` crashed (`ZeroDivisionError` in `project_channels`). A channel
with no `members` list was being scored for the Jira bot. Only `harborline` was being run, so
nothing noticed. This gate would have caught it the day it broke.

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
