# Dogfooding autopilot

All runs used real `claude -p` sessions (Claude Code 2.1.331, `--model sonnet`) with the
plugin loaded through `--plugin-dir plugins/autopilot`. Each ran in a fresh copy of
`examples/demo-repo` made by `examples/setup-demo.sh`. Transcripts were recorded with
`--output-format stream-json --include-hook-events` and condensed with
`docs/evidence/extract_run.py`. The condensed files are in `docs/evidence/`.
`<scratch>`, `<demo>` and `<repo>` replace local paths.

The human approval step was simulated: the session stopped at `plan_review`, and the
driver resumed it with `--resume <session> "Plan approved as written. Continue the run to the end."`.

## Summary

| Run | Pattern | Result | Cost (sonnet) |
|---|---|---|---|
| Task 1 `01-default.md` | default | planner → plan-check ok → **stopped for plan approval** → test-writer → red-check RED OK → implementer passed the gate on attempt 1 → reviewer `[]` → integration gate PASS → summary, waiting for human | $0.16 + $0.35 |
| Task 2 `02-fanout.md`, first attempt | fan-out | **Found a design bug.** Both slices escalated at 3/3, and the orchestrator stopped without merging | $0.19 + $0.45 |
| Task 2 `02-fanout.md`, after the fix | fan-out | 2 disjoint slices → 2 worktrees from the tests commit → parallel implementers, each passing its own slice check on attempt 1 → deterministic merge → integration PASS → reviewer `[]` → final gate PASS | $0.17 + $0.43 |

## Definition-of-done evidence

| Claim | Where it was demonstrated |
|---|---|
| (a) The implementer can't finish with failing tests | Live, main session (small pattern): `evidence/phase3-stop-gate.txt`. Live, subagent: `evidence/phase4-subagent-gate-and-reviewer.txt`. Script tests: `test_gate.sh`, `test_claude_shims.sh` |
| (b) Editing a test or an out-of-scope file blocks the gate | Script tests `test_gate.sh` (tests-changed, scope, protected, `checks.sh`, `config.json`) and `test_claude_shims.sh` (PreToolUse denies, Bash-written test edit caught by the hash check). Live, fan-out v1: implementers saw the other slice's red tests and couldn't touch those files |
| (c) The reviewer can't edit files | Live: `evidence/phase4-subagent-gate-and-reviewer.txt`. The reviewer's own words were "The tools I have are: Read, Grep, Glob", and `git diff --stat` shows `inventory/stock.py` untouched |
| (d) A slice that fails 3 times escalates instead of looping | Live, 3 times: phase 3 (Stop), phase 4 (SubagentStop) and fan-out v1 (two parallel slices, then `autopilot end … escalated`). Script tests check that attempts never pass 3 |
| (e) A reviewer finding without a failing repro is discarded | `evidence/proof-e-findings.txt` (real pytest in the demo repo): a passing repro, a missing repro and an import-error repro are DISCARDED, and the failing-assertion repro is KEPT. Script test: `test_verify_finding.sh` |

### (a)+(d) Main-session Stop gate, live (`evidence/phase3-stop-gate.txt`)
Claude was told to break `apply_discount` and end its turn.
```
ASSISTANT: DONE
HOOK hook_response ... "hook_event": "Stop", "exit_code": 2 ...
  UNIT: <run>/integration  ATTEMPT: 1/3
  VERDICT: FAIL (checks)
  REASON: repo checks failed
  EVIDENCE: $ .claude/checks.sh
    E       assert 200 == 180
    FAILED tests/test_pricing.py::test_apply_discount - assert 200 == 180
  SCOPE: fix only: inventory/pricing.py
(attempt 2/3: blocked again)
(attempt 3/3: {"systemMessage": "autopilot: <run>/integration escalated after max attempts. ..."}, stop allowed)
FINAL success turns= 5
```

### (a)+(c) Subagent gate and read-only reviewer, live (`evidence/phase4-...`)
Hook input actually received, which confirms the identity fields DESIGN §2 D4 relies on:
```
{"event":"PreToolUse","agent_type":"autopilot:implementer","agent_id":"a5fc…","tool":"Edit"}
{"event":"SubagentStop","agent_type":"autopilot:implementer","agent_id":"a5fc…","transcript":".../subagents/agent-a5fc….jsonl"}  ×3 (1/3 block, 2/3 block, 3/3 escalate)
{"event":"SubagentStop","agent_type":"autopilot:reviewer", ...}  (not gated)
```
After the session, `autopilot status` showed `s1  escalated  attempts=3`.

### (e) Findings need proof (`evidence/proof-e-findings.txt`)
```
$ autopilot verify-finding $RUN $RUN_DIR/findings/f1.json
DISCARDED: f1 repro passes (exit 0); no bug demonstrated
$ autopilot verify-finding $RUN $RUN_DIR/findings/f2.json
KEPT: f2 repro fails as claimed (exit 1); tests/test_review_f2.py added to the suite
$ autopilot verify-finding $RUN $RUN_DIR/findings/f3.json
DISCARDED: f3 has no repro test (test_path + test_code required)
$ autopilot verify-finding $RUN $RUN_DIR/findings/f4.json
DISCARDED: f4 repro errored (exit 2), not an assertion failure; see …/findings/f4.log
```

## Task 1: default pattern (`evidence/dogfood-df-default.{1,2}.txt`)
```
SKILL  autopilot:autopilot
$ autopilot start default "validate discounts in apply_discount"      → 20261123-150124
AGENT  autopilot:planner
$ autopilot plan-check …  → plan-check ok: 1 slice(s), pattern default
$ autopilot phase … plan_review                                          (turn ends; human approves)
AGENT  autopilot:test-writer: AUTOPILOT_SLICE: 20261123-150124/tests
HOOK   SubagentStop exit=0 allow                                         (red-check passed at stop)
$ autopilot red-check …   → RED OK: tests fail as expected (exit 1 from: python3 -m pytest …)
$ autopilot tests-done …  → snapshot: 3 test files
AGENT  autopilot:implementer: AUTOPILOT_SLICE: 20261123-150124/pricing-validate
HOOK   SubagentStop exit=0 allow
$ autopilot attempts … pricing-validate → passed 0
$ autopilot commit … "slice pricing-validate"
$ autopilot diff …        → inventory/pricing.py | 8 ++++++--
AGENT  autopilot:reviewer   → ```json []```
$ autopilot gate … integration → PASS: 20261123-150124/integration (attempt 1/3)
$ git diff --stat main...autopilot/20261123-150124
     inventory/pricing.py         |  8 ++++++--
     tests/test_apply_discount.py | 47 +++++++++
```
The run ended waiting for approval: "Do you approve the diff? … I haven't pushed anything or opened a PR."

## Task 2: fan-out pattern

### First attempt: a real design bug, caught by the gate (`evidence/dogfood-df-fanout-v1.*`)
Each slice's gate ran the full `.claude/checks.sh`. In the `stock-remove` worktree,
that suite includes the `bulk_price` tests the test-writer had just committed, and those
are red until the *other* slice merges. Neither slice could pass alone:
```
HOOK   SubagentStop exit=2 BLOCK   UNIT: …/stock-remove  ATTEMPT: 1/3 … AttributeError: module 'inventory.pricing' has no attribute 'bulk_price'
HOOK   SubagentStop exit=2 BLOCK   UNIT: …/bulk-pricing  ATTEMPT: 1/3 … has no attribute 'InsufficientStock'
… 2/3 …
HOOK   SubagentStop exit=0 ALLOW+msg  "…stock-remove (implementer) escalated after max attempts…"
$ autopilot attempts … → escalated 3 / …
$ autopilot end 20261123-150126 escalated
```
The system behaved correctly. Implementers didn't touch out-of-scope files to make the
other slice's tests pass. Attempts capped at 3, and the orchestrator escalated without
merging a partial result. The plan semantics were wrong, though.

**Fix (commit `de7d077`):** a slice with a `check` is gated by that check only. The
`integration` unit always runs the full `checks.sh`. `plan-check` requires a `check` per
slice when there's more than one. New script tests cover this.

**Proposed rule (learning edge, as the skill would phrase it):** "In multi-slice plans,
each slice's `check` runs only that slice's tests; the full suite belongs to the
integration gate."

### After the fix (`evidence/dogfood-df-fanout.{1,2}.txt`)
```
$ autopilot plan-check …  → plan-check ok: 2 slice(s), pattern fan-out
  slices: stock-remove [inventory/stock.py]   check: python3 -m pytest -q tests/test_stock.py
          bulk-price   [inventory/pricing.py] check: python3 -m pytest -q tests/test_pricing.py
(human approves)
AGENT  autopilot:test-writer → $ autopilot red-check … → RED OK (exit 1)
$ autopilot tests-done … && autopilot worktree … stock-remove && autopilot worktree … bulk-price
    <demo>/.autopilot/worktrees/20261123-150440/stock-remove
    <demo>/.autopilot/worktrees/20261123-150440/bulk-price
AGENT  autopilot:implementer: AUTOPILOT_SLICE: 20261123-150440/stock-remove   (parallel)
AGENT  autopilot:implementer: AUTOPILOT_SLICE: 20261123-150440/bulk-price     (parallel)
HOOK   SubagentStop exit=0 allow   ×2
$ autopilot attempts … → passed 0 / passed 0
$ autopilot merge … && autopilot gate … integration
    merged stock-remove
    merged bulk-price
    PASS: 20261123-150440/integration (attempt 1/3)
AGENT  autopilot:reviewer → no findings
$ autopilot gate … integration → PASS
$ git diff --stat main...autopilot/20261123-150440
     inventory/pricing.py  |  8, inventory/stock.py | 6, tests/test_pricing.py | 24, tests/test_stock.py | 37
```
The branch history is test commit → two slice branches → two `--no-ff` merges, in plan
order.

## Other observations
- **The test-writer wrote tests with `cat >> … <<EOF` through Bash**, not the Write tool, so
  PreToolUse never saw those writes. `red-check` (only test files changed, tests fail
  with exit 1) is what verified them. That's why the end-of-unit gates, not
  PreToolUse, are the verdict.
- Agents typed `python` instead of `python3`, which the first driver's allowlist
  denied. This was an environment issue and didn't affect any verdict. The second
  fan-out run allowed both.
- Both reviewers returned `[]`. That's the intended, honest outcome for small, correct
  diffs. The prompt explicitly says that zero findings is normal.
- In both cases the orchestrator used exact command output for the summary's
  "Evidence" section, and stopped at the human approval step without pushing.
