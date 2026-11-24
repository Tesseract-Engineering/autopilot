---
name: run
description: Run a coding task through autopilot's gated agent graph (planner, test-writer, implementer, read-only reviewer; pass/fail decided by scripts). Use when the user types /autopilot:run.
argument-hint: "<task description or path to a task file>"
disable-model-invocation: true
---
Run this task with autopilot:

$ARGUMENTS

1. Load the `autopilot` skill (the playbook) and follow it exactly. It holds the router,
   the patterns, the subagent prompt templates and the rules.
2. If the task text above is a path to a file, read it first.
3. Start by running `autopilot help` to confirm the CLI is on PATH. If it isn't, stop
   and tell the user the plugin isn't installed correctly.
