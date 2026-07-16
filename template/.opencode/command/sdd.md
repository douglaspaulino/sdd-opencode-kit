---
description: Runs the mandatory 5-step SDD pipeline on task files.
---

Load the sdd-pipeline skill first.

## Resolve tasks

$ARGUMENTS = single file or directory.
- File: one task.
- Directory: glob `$ARGUMENTS/*.md`, sorted alphabetically.
- No tasks → tell user, stop.

## Branch setup

Before any task execution, ask the user:

> Create a new branch for this SDD run? (y/n)

If **yes**:
1. Record the current branch: `ORIG_BRANCH=$(git branch --show-current)`.
   If in detached HEAD, ask the user which branch to merge back to.
2. Create and switch to a new branch:
   `git checkout -b sdd/<slug-from-first-task>`.
3. Store metadata in `.sdd/branch.json`:
   ```json
   { "original_branch": "main", "sdd_branch": "sdd/issue-42" }
   ```
4. All subsequent work happens on this branch.

If **no**: work on the current branch directly. Skip branch metadata.

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

## Branch teardown

If a branch was created (`.sdd/branch.json` exists):

1. Print the branch name and completion status for all tasks.
2. Ask the user:
   > Merge `sdd/<branch>` back into `<original_branch>`? (y/n)
3. If **yes**:
   - `git checkout <original_branch>`
   - `git merge sdd/<branch> --no-ff -m "sdd: merge completed SDD cycle"`
   - `git branch -d sdd/<branch>`
   - `rm .sdd/branch.json`
4. If **no**: stay on the SDD branch for manual review. Tell the user
   the branch name and how to merge or discard it.
