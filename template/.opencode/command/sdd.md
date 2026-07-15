---
description: Runs the mandatory 5-step SDD pipeline on task files.
---

Load the sdd-pipeline skill first. Then process the user's request using
$ARGUMENTS as the input path.

## Resolve tasks

1. Determine if $ARGUMENTS is a single file or a directory.
   - If a file: treat it as the only task.
   - If a directory: glob `$ARGUMENTS/*.md` (non-recursive), sorted
     alphabetically.
2. If no tasks found, tell the user and stop.

## Process each task

For every task file found, execute the pipeline in strict order. The
pipeline steps and state format are defined in the sdd-pipeline skill
(loaded above). Always:

- Read the task file content and derive `task-id` from its filename
  (lowercase, path-safe, hyphen-separated).
- Read `.sdd/runs/<task-id>/state.json` if it exists.
- Resume from the first step with status `pending` (skip `completed` and
  `in_progress` steps are treated as incomplete and restarted).
- If no state file exists, create a fresh one with all steps `pending`.
- Run each step using the Task tool with the corresponding subagent:
  `sdd-implementer`, `sdd-task-reviewer`, `sdd-fixer`,
  `sdd-code-reviewer`, `sdd-verifier`.
- Pass the task file content and all prior step reports as context to
  each subagent.
- After each step completes, update `state.json` and write the step's
  report to `.sdd/runs/<task-id>/<step>-report.md`.
- If the verifier rejects (status `failed`) and attempts < 3, loop back
  to the fixer → code-reviewer → verifier sequence.
- If max attempts (3) are reached with verifier still failing, mark the
  task `failed` and move to the next one.

## Summary

After all tasks are processed, print a summary table with:
- Task file name
- Final status (completed / failed)
- Which step each failed task was stuck on
- Total attempts used
