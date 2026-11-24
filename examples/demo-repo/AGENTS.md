# Agent rules for demo-repo

<!-- autopilot:begin -->
- Checks: `.claude/checks.sh` (pytest). It must pass before any change is done.
- Tests live in `tests/`. Implementers never edit tests; tests are the spec.
- `migrations/` is protected: no agent edits it.
- Keep functions small and pure; no new dependencies.
<!-- autopilot:end -->
