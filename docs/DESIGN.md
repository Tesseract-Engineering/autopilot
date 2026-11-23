# autopilot: design

Status: **draft for review**. Nothing below is built yet.
Docs read on 2026-11-23 against Claude Code 2.1.331: plugins-reference, plugin-marketplaces, hooks, sub-agents, worktrees, best-practices, and the two Anthropic engineering posts. Codex docs (hooks, plugins, subagents) were read for the portability notes.

## 1. Core idea

Programs decide pass/fail and models do the work. Every verdict is an exit code from a bash script in `core/scripts/`. Hooks only call those scripts and translate the exit code into the harness's block format. No `prompt` or `agent` hook is used anywhere.

## 2. Where the docs differ from the brief

| # | Brief says | Docs say (2.1.331) | Decision |
|---|---|---|---|
| D1 | `commands/` for `/autopilot:run` and `/autopilot:init` | "Commands are the older format… Prefer `skills/` for new plugins." Skills are namespaced `/<plugin>:<dir>`. | Use `skills/run/` and `skills/init/` (both `disable-model-invocation: true`) and `skills/autopilot/` for the router. Engineers type `/autopilot:run "<task>"` and `/autopilot:init`. No `commands/` directory. |
| D2 | `isolation: worktree` branches from the default branch | Confirmed, unless the `worktree.baseRef: "head"` setting is set. That setting is per user or per project and can't be scoped to a single subagent. | **We create worktrees ourselves** (`core/scripts/worktree.sh`) with `git worktree add` from the run branch's HEAD, after the plan and the tests are committed there. No agent uses `isolation: worktree`. See §6. |
| D3 | Stop hook has a consecutive-block cap | The cap is **8** consecutive continuations (`CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`). The counter **resets whenever Claude calls a tool**, so an agent that keeps editing never reaches it. | The cap can't be relied on to stop a loop. `attempts.sh` (cap 3, below 8) is the real stop. When attempts run out, the gate **allows** the stop and marks the slice `escalated`, so the loop ends cleanly rather than being cut off by the harness. |
| D4 | "SubagentStop if the input lets us tell agents apart" | It does. `SubagentStop` and `PreToolUse` inside a subagent carry `agent_id`, `agent_type` and `agent_transcript_path`. Plugin agents are named `autopilot:<name>`. | Gate per role: the implementer gets the full gate, the test-writer gets the red check, the planner and reviewer are not gated. **Verified live:** `agent_type` is `"autopilot:implementer"` and so on, and the slice marker is read from the real `agent_transcript_path` (docs/evidence/phase4-*). |
| D5 | Plugin agents ignore `hooks`, `mcpServers`, `permissionMode` | Confirmed. `initialPrompt` is ignored too. | All enforcement goes in `hooks/hooks.json`. Tool limits use `tools` / `disallowedTools`. |
| D6 | Worktrees lack gitignored files and deps | Confirmed. `.worktreeinclude` (gitignore syntax, copies only files that are ignored) is applied only to worktrees that Claude creates. | Because we create worktrees ourselves (D2), `worktree.sh` applies `.worktreeinclude` itself, then runs the optional `.autopilot/setup.sh` (for example `pip install -e .`). |
| D7 | Plugin = `plugins/autopilot/` generated from `core/` | An installed plugin is copied into a cache. Only the plugin directory ships, so `../../core` isn't reachable at runtime. Hook paths use `${CLAUDE_PLUGIN_ROOT}`. | `build.sh` **copies** `core/scripts`, `core/skills` and `core/roles` into `plugins/autopilot/`. `build.sh --check` fails if the generated files drift from `core/`, and CI runs it. |
| D8 | — | Exit codes: `0` is pass, `2` blocks with stderr fed back to Claude, any other code is **non-blocking**. A hook that times out does not block. | The shims map every non-zero core verdict to exit 2. A crash inside the gate script also blocks (fail closed): the shim catches it and exits 2 with the message "gate crashed: …". Hook timeout is set explicitly (600s, the documented default). |

## 3. The graph

```
/autopilot:run "<task>"
        │
   ROUTER (skill) ── classify ─┬─ small      → implement ⟲ gate → human
                               ├─ default    → plan → [approve] → tests → implement ⟲ gate → review → human
                               ├─ fan-out    → plan(slices) → [approve] → tests → N× implement ⟲ gate (worktrees)
                               │                → merge.sh → integration gate → review → human
                               ├─ best-of-N  → N× implement ⟲ gate (worktrees) → pick.sh → review → human
                               └─ bug-fix    → repro test (red) ── none? STOP & ask → implement ⟲ gate → human
```

Router rules, deterministic where possible and decided by the orchestrator otherwise:
- **small**: one file or an obvious change of ≤ ~30 lines, with no new behavior that needs a spec. Runs as a single agent in the main session, and the Stop hook is the gate. This is the default the router falls back to when unsure.
- **bug-fix**: the task describes broken behavior. The test-writer must produce a repro that fails `red-check.sh`. If no failing repro is produced, the run stops and asks the human.
- **default**: new behavior where the files touched share context.
- **fan-out**: only when the plan's slices have **pairwise-disjoint `allowed_files`**. `plan-check.sh` verifies this. If the check fails, the run falls back to default.
- **best-of-N**: the human asks for it, or a bug-fix slice escalates and the human chooses to retry wide. N defaults to 3.

The skill says in so many words when **not** to use the graph: exploratory or design questions, changes with no deterministic check, tasks where the human wants to pair, and anything the 15× token cost can't justify.

## 4. Roles (`core/roles/*.md` → `plugins/autopilot/agents/*.md`)

| Role | Sees | Tools (frontmatter) | Writes | Gated by |
|---|---|---|---|---|
| planner | task, repo (read) | Read, Grep, Glob, Write | `.autopilot/runs/<id>/plan.md` + `slices.json` only | `plan-check.sh` (schema, disjoint, globs non-empty) run by the orchestrator |
| test-writer | task + plan **spec sections only**; told not to read implementation files of the slice | Read, Grep, Glob, Write, Edit, Bash | files matching `test_globs` only | SubagentStop → `red-check.sh`: changed ⊆ test_globs **and** `test_cmd` fails |
| implementer | one slice: spec, allowed files, failing tests | Read, Grep, Glob, Write, Edit, Bash | allowed files of its slice | SubagentStop → `gate.sh` |
| reviewer | spec + `git diff` (passed in prompt as text/file), fresh context | **Read, Grep, Glob only** (`disallowedTools: Write, Edit, NotebookEdit, Bash`) | nothing; returns findings as text | n/a; findings verified by `verify-finding.sh` |

The test-writer is kept independent by instruction and by input selection: it is given only the spec, not paths into the slice's code. Read access is not technically removed, since it may need to read public interfaces. This is guidance, not enforcement, and the reason is stated here: the rule has exceptions.

## 5. Enforcement (only zero-exception rules)

`plugins/autopilot/hooks/hooks.json` → `scripts/claude/*.sh` shims → `scripts/*.sh` core.

| Hook | When it acts | Rule |
|---|---|---|
| `PreToolUse` (Edit\|Write\|NotebookEdit) | always, if `.autopilot/config.json` exists | Deny writes to `protected_paths` from any agent. Deny writes to `test_globs` from `autopilot:implementer`. Deny all writes from `autopilot:reviewer` (belt and braces on top of `tools`). |
| `SubagentStop` | `agent_type` = `autopilot:implementer` / `autopilot:test-writer` | Run `gate.sh` / `red-check.sh` for that agent's slice. |
| `Stop` (main session) | **only** while a run is active and its phase is `implement` (small pattern) or `final` | Run `gate.sh` on the run's scope. In any other state (no run, plan review, escalated) it exits 0. A plugin installed for the whole org must not hijack ordinary sessions. |

Bash can write files without going through PreToolUse, so `gate.sh` re-checks everything at the end of the slice (scope and test hashes). PreToolUse gives early feedback. The gate is the verdict.

**Which slice is stopping?** The orchestrator puts a first line `AUTOPILOT_SLICE: <run_id>/<slice_id>` in every implementer and test-writer prompt. The shim reads the first user message from `agent_transcript_path` (JSONL) to find it, then caches `agent_id → slice` in the run dir. If no marker is found, the shim blocks with "missing AUTOPILOT_SLICE marker", which fails closed. This gets checked in phase 3. Fallback if transcript parsing turns out to be unreliable: implementers run one at a time, with `.autopilot/runs/<id>/active-slice` as the pointer. That fallback would make fan-out sequential.

### `gate.sh <run_id> <slice_id>` (in the slice's worktree)
In order, stopping at the first failure:
1. `attempts.sh check`: if the slice is already at max, exit 0 with `ESCALATED`. That lets the agent stop, and the orchestrator escalates.
2. `scope-check.sh`: `git diff --name-only <slice_base>` plus untracked files, minus `.autopilot/`, must be ⊆ the slice's `allowed_files` globs. Files under `protected_paths` always fail.
3. `tests-unchanged.sh`: the sha256 of every file matching `test_globs` must match the manifest snapshotted right after the test-writer commit. Added and deleted test files count as changes.
4. Checks. A slice that has a `check` runs only that check. The other slices' new tests are still red until merge, which was **found in dogfooding**: see DOGFOOD.md. The `integration` unit, and a slice without a `check`, run `.claude/checks.sh`. `plan-check` requires a `check` on every slice when a plan has more than one.

On failure it runs `attempts.sh incr`, writes `gate-<n>.log` to the run dir, and prints to stderr (≤ ~50 lines):
```
UNIT: <run>/<slice>  ATTEMPT: 2/3
VERDICT: FAIL (scope|tests-changed|checks)
REASON: <one line>
EVIDENCE: <failing command> / <file:line list> / first 40 lines of output
SCOPE: fix only: <allowed_files>
```
Exit 1 means fail. The Claude shim turns that into exit 2. When the attempt that just failed was the last one, the gate marks the slice `escalated`, prints `ESCALATE: …` and exits 0 so the agent stops. The orchestrator reads `attempts.sh status` and stops the run for the human.

### Other core scripts
- `attempts.sh {incr|check|status|reset} <run> <slice>`: a counter file per slice, with `max_attempts` from config (default 3).
- `red-check.sh`: changed ⊆ `test_globs`, and `test_cmd` exits with one of the codes in `repro_fail_codes` (default `[1]`, pytest's code for "tests failed", as opposed to 2+ for errors).
- `snapshot-tests.sh`: writes `tests.sha256` after the test-writer commit.
- `worktree.sh <run> <slice>`: runs `git worktree add -b autopilot/<run>/<slice> .autopilot/worktrees/<run>/<slice> HEAD`, copies `.worktreeinclude` matches, runs `.autopilot/setup.sh` if present, and writes `.autopilot/slice` in the worktree.
- `merge.sh <run>`: merges slice branches in `slices.json` order with `git merge --no-ff`. A conflict means a `git merge --abort` and exit 1, and the run escalates, because the slices were supposed to be file-disjoint.
- `pick.sh <run>`: for best-of-N, takes the candidates whose gate passed and picks the one with the smallest `insertions+deletions`. Ties go to the lowest index.
- `verify-finding.sh <run> <finding_dir>`: writes the reviewer's repro test into the candidate tree, runs its command, and **keeps the finding only if the exit code is in `repro_fail_codes`**. It then removes the repro. Discarded findings are logged with the reason.
- `plan-check.sh <run>`: checks that `slices.json` parses, every slice has `allowed_files` and `check`, and slices are disjoint when the mode is fan-out.

## 6. Worktree strategy (D2)

1. The orchestrator creates the branch `autopilot/<run_id>` from the current HEAD.
2. The planner writes the plan. The plan is committed (`.autopilot/runs` is gitignored, so `plan.md` is copied to `docs/autopilot/<run_id>.md` only if the human wants it kept. Otherwise the plan lives in the run dir and paths are passed to agents directly).
3. The test-writer writes tests on the run branch in the main checkout. Red-check runs, then the tests are committed and `snapshot-tests.sh` runs.
4. Small, default and bug-fix patterns: the implementer works in the main checkout on the run branch. No worktree.
5. Fan-out and best-of-N: `worktree.sh` per slice, created from the run branch HEAD, which already has the tests. Each implementer is told to work only under its absolute worktree path.
6. After merge and the integration gate, worktrees are removed (`git worktree remove`).

The human approves the diff `main...autopilot/<run_id>`. autopilot never pushes.

## 7. Per-repo contract (`/autopilot:init`)

```
.claude/checks.sh            # repo checks; exit 0 = pass. Generated skeleton detects pytest/npm/go/cargo; human edits.
.autopilot/config.json       # see below
.autopilot/setup.sh          # optional: deps install inside a fresh worktree
.worktreeinclude             # optional
.gitignore                   # += .autopilot/runs/ .autopilot/worktrees/
AGENTS.md                    # repo rules, harness-neutral (created or appended in a marked block)
CLAUDE.md                    # gets "@AGENTS.md" import line if missing
```
```json
{
  "test_globs": ["tests/**", "**/test_*.py"],
  "protected_paths": ["migrations/**"],
  "max_attempts": 3,
  "require_plan_approval": true,
  "test_cmd": ".claude/checks.sh",
  "repro_fail_codes": [1]
}
```
Run dir `.autopilot/runs/<id>/`: `state.json` (pattern, phase, branch), `plan.md`, `slices.json`, `tests.sha256`, `attempts/<slice>`, `gate-*.log`, `findings/`, `summary.md`. This is the external memory that survives context compaction. The skill tells the orchestrator to re-read `state.json` after compaction.

**Learning edge:** `summary.md` ends with "Proposed CLAUDE.md/AGENTS.md rules", one line per real failure caught. These are never written to the file automatically.

## 8. Repo layout

```
.claude-plugin/marketplace.json          # name: autopilot, plugins: [{name: autopilot, source: ./plugins/autopilot}]
core/
  scripts/*.sh                           # harness-neutral; args + exit codes; need bash, git, jq
  skills/autopilot/SKILL.md              # router + patterns, role-based wording (no Claude tool names)
  skills/{run,init}/SKILL.md
  roles/{planner,test-writer,implementer,reviewer}.md   # prompt + YAML metadata (allowed capabilities)
  tests/*.sh                             # plain-bash test runner (bats not installed; no extra dep)
adapters/
  claude/agent-frontmatter/*.yml         # role → Claude frontmatter (tools, disallowedTools, model)
  claude/hooks.json
  claude/shims/{pretooluse,subagent-stop,stop}.sh   # parse hook JSON → call core → exit 2 + stderr
  git/pre-push, git/autopilot-gate.yml   # backstop: checks.sh + protected paths vs merge-base
  codex/README.md                        # what's needed + blockers (below)
plugins/autopilot/                       # GENERATED by build.sh. Never hand-edit.
  .claude-plugin/plugin.json
  agents/*.md  skills/*/SKILL.md  hooks/hooks.json  scripts/
examples/demo-repo/                      # tiny Python package (pytest) + tasks/{01-default.md,02-fanout.md}
build.sh                                 # generate; --check for drift
docs/DESIGN.md docs/DOGFOOD.md README.md
```

## 9. Codex adapter (v1: README only)
Notes from the Codex docs:
- Codex has `Stop` and `SubagentStop`. `decision:"block"` or exit 2 **continues** the turn with the reason. That is the same semantics we rely on, so it is fine.
- Plugins can bundle hooks (`.codex-plugin/plugin.json` → `hooks/hooks.json`).
- **Blocker:** non-managed hooks have to be trusted by each user through `/hooks`, and re-trusted after every change. The gate is therefore not active by default after install.
- **Blocker:** Codex agent TOML has no per-agent tool allow-list, and agents inherit the parent's sandbox. A read-only reviewer can't be enforced per agent, so it would need a separate read-only-sandbox invocation.
- Whether `SubagentStop` input identifies the agent type was not confirmed and needs checking.

## 10. Proof plan (definition of done)
| Claim | Demonstration |
|---|---|
| (a) can't finish with failing tests | Demo repo: the implementer (and, in the small pattern, the main session) breaks a test. The Stop/SubagentStop hook blocks with the gate stderr. Transcript excerpt goes in DOGFOOD.md. |
| (b) test / out-of-scope edit blocks | Core tests plus a live run: an edit to `tests/` is denied by PreToolUse, and an edit to a test made via Bash is caught by `tests-unchanged`. A file outside the slice → scope FAIL. |
| (c) reviewer can't edit | Live: the reviewer is asked to fix something. The tool isn't available, and PreToolUse would deny it anyway. |
| (d) 3 failures escalate | Core test plus a live run with an impossible slice: attempt 3 → `ESCALATE`, agent stops, run state `escalated`. |
| (e) unproven finding discarded | Core test plus live: a finding whose repro passes is logged as discarded. A finding whose repro fails is kept. |

Plus `claude plugin validate .` (and `--strict`), `core/tests/run.sh`, and `build.sh --check`, with their real output pasted into the PR.

## 11. Decisions (answered 2026-11-23)
1. **JSON tooling:** use `jq` for quick reads and filters (config, state, slices), and `python3` (stdlib only) for logic with state or error handling: glob matching with `**`, parsing hook input and transcripts. Requirements: bash, git, jq, python3.
2. **Gating:** hooks act **only while an autopilot run is active**. Ordinary sessions are never gated. During a run, implementer and test-writer subagents are gated at SubagentStop, and the main session is gated at Stop in the `implement` (small) and `final` phases.
3. **Plans** stay in the gitignored run dir.
4. **Public repo:** pushing `feat/v1` and opening a PR is fine.

The bar is features that ship and work, without over-engineering. That simplifies three things:
- Fan-out slices list **literal file paths**, not globs. Disjointness is then a duplicate check with no overlap reasoning.
- The gate has three outcomes: exit 0 = pass, 1 = fail, 3 = escalated. Any other code means the gate crashed, and the shim blocks with the crash output.
- Hook transcripts confirmed: in a subagent transcript, the first JSONL line is `{"type":"user","message":{"content":"<prompt>"}}`, so the slice marker can be read from it.
