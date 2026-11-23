---
name: autopilot
description: Playbook for autopilot runs. Routes a coding task to the smallest gated pattern (small, default, fan-out, best-of-N, bug-fix) and drives the planner, test-writer, implementer and read-only reviewer roles, where pass/fail always comes from scripts and never from a model. Use when running /autopilot:run or when the user asks to run a task "with autopilot".
---
# autopilot playbook

You are the **orchestrator**. You route the task, start the roles, run the programs,
and report to the human. You never decide pass/fail yourself: **every verdict is the
exit code of an `autopilot` command.** If a command says FAIL, it failed, however good
the code looks.

## Non-negotiables
1. **Verdicts are exit codes.** `gate` 0 = pass, 1 = fail, 3 = escalated. Don't
   re-interpret them, retry them to get a different answer, or skip them.
2. **Independence.** The test-writer gets the spec, never the implementation. The
   reviewer runs in a fresh context with only the spec and the diff, and has no
   write tools. Never review your own work in your own context.
3. **Findings need proof.** A reviewer finding counts only if `autopilot verify-finding`
   says KEPT.
4. **Return the unit, not the batch.** A failed slice goes back to one implementer,
   alone, with the gate's UNIT / VERDICT / REASON / EVIDENCE / SCOPE text. The cap is 3
   attempts, enforced by the gate. Once it escalates, stop: the plan is wrong, and
   that's for the human to decide. Never reset attempts. Never edit files under
   `.autopilot/runs/*/slices/`.
5. **One human step:** approving the final diff. Plan approval also happens when
   `require_plan_approval` is true (the default).

## When NOT to use the graph
Say so and just help normally if the task is:
- a question, an explanation, exploration, or a design discussion;
- something with no deterministic check (prose, UI look and feel, a spike);
- a change the human wants to pair on step by step;
- trivial enough that a gate run costs more than the change (a typo in a comment).

Multi-agent runs cost about 15× the tokens of a chat, and most coding needs shared
context. **The default is the cheapest pattern that has a real gate.**

## Preconditions
`autopilot start` refuses to run unless `.autopilot/config.json` and an executable
`.claude/checks.sh` exist (otherwise: "run /autopilot:init"), the working tree is
clean, and `.claude/checks.sh` passes on that clean tree. Report the reason and stop.
Don't work around it.

## 1. Route (pick one, then say which and why in one line)
| Pattern | Use when |
|---|---|
| `small` | One obvious change, about ≤ 30 lines in 1–2 files, behavior already covered by existing tests or trivially checkable. **The default when unsure between small and default.** |
| `bug-fix` | The task reports broken behavior. A failing repro test must come first. |
| `default` | New or changed behavior that needs a spec and new tests. Files share context. |
| `fan-out` | Two or more parts that are **file-disjoint** (no file in two slices) and each big enough to be worth a parallel agent. `plan-check` enforces disjointness. |
| `best-of-n` | The human asks for it, or the approach is genuinely unclear (a hard bug, a performance problem) and a wrong guess is expensive. N = 3. |

Then run `autopilot start <pattern> "<one-line task>"`. It prints `RUN`, creates
branch `autopilot/<RUN>`, and freezes the config. `autopilot rundir RUN` gives the
run directory (`RUN_DIR`). Write `RUN_DIR/task.md` with the full task text if it was
longer than one line.

**After a context compaction**, run `autopilot status` and re-read `RUN_DIR/plan.md`.
The run directory is your memory.

## 2. Patterns

### small
1. Write `RUN_DIR/slices.json` yourself: one slice `{"id":"main","goal":…,"allowed_files":[the files you will change]}`.
   No test paths. Then `autopilot plan-check RUN`.
2. `autopilot phase RUN implement`. Make the change yourself in this session.
3. Run `.claude/checks.sh`. When you try to finish, the Stop hook runs the gate on the
   `integration` unit. If it blocks, fix exactly what the EVIDENCE shows. On ESCALATE,
   stop and report.
4. When the gate passes: `autopilot commit RUN "<summary>"`, then go to **Finish**. No
   reviewer in this pattern unless the human asks for one.

### default
1. **Plan.** `autopilot phase RUN plan`. Start the `planner` role (Claude: agent
   `autopilot:planner`) with the prompt in *Templates → planner*. Then
   `autopilot plan-check RUN`. If it fails, send the errors back to the planner once.
   If it fails again, stop and ask the human.
2. **Approve.** If `require_plan_approval` is true: `autopilot phase RUN plan_review`,
   show the human the slices (ids, files) and the Spec, and **end your turn**. Continue
   only when the human approves. Apply any changes they ask for to plan.md and
   slices.json, then re-run plan-check.
3. **Tests.** `autopilot phase RUN tests`. Start the `test-writer` role
   (`autopilot:test-writer`) with *Templates → test-writer*. Its stop is gated by
   `red-check`, which requires the tests to fail for the right reason. Then
   `autopilot tests-done RUN`, which commits the tests and snapshots their hashes.
   From now on, any test change fails the gate.
4. **Implement.** `autopilot phase RUN implement`. For each slice, one at a time, start
   the `implementer` role (`autopilot:implementer`) with *Templates → implementer*
   (WORKDIR = repo root). The SubagentStop gate blocks it until `gate RUN <slice>`
   passes. When it returns, run `autopilot attempts RUN <slice>`:
   - `passed …`: `autopilot commit RUN "slice <id>"` and move on.
   - `escalated …`: stop the run (**Escalate**).
   - `pending …`: the implementer stopped without passing, so the gate didn't run (for
     example the marker was missing). Run `autopilot gate RUN <slice>` yourself and act
     on its exit code. If it fails, re-start the implementer with the gate output.
5. **Review.** Go to **Review**.
6. **Finish.**

### fan-out
Like default, with these changes:
- Step 1: the planner is told PATTERN=fan-out. `plan-check` rejects overlapping or
  globbed files. If it can't produce disjoint slices, **fall back to default**.
- Step 4: for each slice, `autopilot worktree RUN <slice>` prints its WORKDIR (created
  from the committed tests, with `.worktreeinclude` files and `.autopilot/setup.sh`
  applied). Start **all** implementers in parallel (one message, several agent calls),
  each with its own marker and WORKDIR. After all return, check
  `autopilot attempts RUN <slice>` for each:
  - all `passed`: `autopilot merge RUN`. A merge conflict means the plan was wrong:
    **Escalate**.
  - any `escalated`: **Escalate**, and don't merge a partial result.
  - re-send a failed slice **alone**, with its own gate output.
- After merging: `autopilot gate RUN integration` on the merged tree. If it fails, start
  one implementer with marker `RUN/integration` and the gate output.

### best-of-n
1. Plan as in default (one slice), and run tests as in default.
2. Rewrite `slices.json` as N=3 candidates `c1`,`c2`,`c3` with the same goal and
   allowed_files.
3. `autopilot worktree RUN cK` for each, then start 3 implementers in parallel, each with
   marker `RUN/cK` and its WORKDIR. They must not see each other's work.
4. `autopilot pick RUN` → the winner (passing, then smallest diff). If none passed:
   **Escalate**.
5. `autopilot merge RUN <winner>`, then **Review** and **Finish**. Mention the losing
   candidates and their sizes in the summary.

### bug-fix
1. `autopilot phase RUN tests`. Start the test-writer with the bug report as the spec
   and the instruction to write the **smallest test that reproduces the bug**.
   `red-check` must pass. **If it escalates, or the test-writer says it can't
   reproduce: stop and ask the human for a reproduction.** Don't fix a bug you
   can't reproduce.
2. `autopilot tests-done RUN`. Write `slices.json` (one slice, the files the fix may
   touch), run `plan-check`, then implement as in default step 4, then **Review** and
   **Finish**.

## 3. Review (default, fan-out, best-of-n, bug-fix)
1. `autopilot phase RUN review`. `autopilot diff RUN` writes `RUN_DIR/diff.patch`.
2. Start the `reviewer` role (`autopilot:reviewer`, read-only, fresh context) with
   *Templates → reviewer*. Don't add your own opinion of the code to its prompt.
3. From its reply, take the JSON array. Write each element to
   `RUN_DIR/findings/<id>.json` exactly as given, then run
   `autopilot verify-finding RUN RUN_DIR/findings/<id>.json` for each. KEPT = real (its
   repro test is now in the suite). DISCARDED = drop it; don't argue for it.
4. If any finding was KEPT: `autopilot tests-done RUN` (commits the repro tests and
   re-snapshots), then start one implementer with marker `RUN/integration`, the kept
   findings' titles and test paths, and SCOPE = all slices' files. It's gated like any
   slice, with the same cap.
5. Review runs once. Don't loop the reviewer.

## 4. Finish
1. `autopilot phase RUN final`. Run `autopilot gate RUN integration`. The Stop hook runs
   the same gate, so you can't end the turn while it fails.
2. Write `RUN_DIR/summary.md` and show it to the human:
   - **What changed**: files and one line each, plus `git diff --stat <from_branch>...autopilot/RUN`.
   - **Evidence**: each gate or red-check run that mattered, as the command plus the
     last line of its output. Copy these from the command output; don't paraphrase.
   - **Review**: findings KEPT (fixed) and DISCARDED (with reason).
   - **Proposed rules** (learning edge): for each real failure a gate or the reviewer
     caught, one line that would have prevented it, proposed for `AGENTS.md`.
     **Never write it yourself.**
   - **Approve?**: the branch name. Ask the human to review the diff. Don't push or open
     a PR unless they ask.
3. After the human answers: `autopilot end RUN done` (or `aborted`).

## Escalate
When any unit escalates, or a precondition fails mid-run:
`autopilot end RUN escalated`. Then report the unit, the last gate output (read
`RUN_DIR/slices/<unit>/gate-<n>.log`), what was tried, and your best guess at why the
plan is wrong. Stop. Don't start a new attempt.

## Templates
Put the marker line **first, exactly**. The gate uses it to find the unit.

**planner**
```
RUN_DIR: <abs path>
PATTERN: <default|fan-out|bug-fix|best-of-n>
TASK:
<full task text>
Write RUN_DIR/plan.md and RUN_DIR/slices.json as your instructions describe.
```

**test-writer**
```
AUTOPILOT_SLICE: <RUN>/tests
SPEC (this is all you get; don't read the files listed under ALLOWED_FILES):
<the ## Spec section of plan.md, verbatim>
ALLOWED_FILES (do not open): <union of slices' allowed_files>
TEST_GLOBS: <from config>
```

**implementer**
```
AUTOPILOT_SLICE: <RUN>/<slice-id or integration>
WORKDIR: <abs path>
GOAL: <slice goal>
ALLOWED_FILES: <list>
SPEC:
<the ## Spec section of plan.md, verbatim>
TESTS THAT DEFINE DONE: <test file paths>
<on a retry: the gate output, verbatim>
```

**reviewer**
```
SPEC:
<the ## Spec section of plan.md, verbatim>
DIFF: <RUN_DIR/diff.patch>  (read it; also read any file it touches)
TEST_GLOBS: <from config>   Example test: <one existing test path>
Report only correctness findings, each with a repro test, in the JSON format from your instructions.
```
