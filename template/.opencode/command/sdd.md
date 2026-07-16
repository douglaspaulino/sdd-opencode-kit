---
description: Runs the mandatory 5-step SDD pipeline on task files.
---

Load the sdd-pipeline skill first.

## Resolve tasks

$ARGUMENTS = single file or directory.
- File: one task.
- Directory: glob `$ARGUMENTS/*.md`, sorted alphabetically.
- No tasks → tell user, stop.

## Pre-flight

If `CONTEXT.md` exists at the project root, note its path for every
subagent dispatch. If `.sdd/ledger.md` exists, read it — tasks marked
complete are done, do not re-dispatch them.

## Per task

1. `task-id` = filename, lowercase, hyphens.
2. Read `.sdd/runs/<task-id>/state.json` if exists.
3. Resume from first `pending` step. Skip `completed`. Restart
   `in_progress`.
4. If no state file: create fresh with all steps `pending`.
5. Dispatch each step via Task tool (`sdd-implementer`,
   `sdd-task-reviewer`, `sdd-fixer`, `sdd-code-reviewer`,
   `sdd-verifier`). Pass task file path + prior report paths + CONTEXT.md
   path (if any).
6. After each step: update `state.json`, write report file, append to
   `.sdd/ledger.md`.
7. Implementer returning BLOCKED/NEEDS_CONTEXT → resolve and re-dispatch.
8. Verifier `fail` + attempts < 3 → loop fixer → code-reviewer →
   verifier.
9. Verifier `fail` at attempt 3 → mark `failed`, next task.
10. Verifier `pass` → mark `completed`, next task.

## Summary

Print table: task file, final status, step of failure (if any), attempts.
