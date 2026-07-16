---
description: Runs the mandatory 5-step SDD pipeline on task files.
---

Load the sdd-pipeline skill first.

## Resolve tasks

$ARGUMENTS = single file or directory.
- File: one task.
- Directory: glob `$ARGUMENTS/*.md`, sorted alphabetically.
- No tasks → tell user, stop.

## Worktree setup

Before any task execution, ask the user:

> Create an isolated git worktree for this SDD run? (y/n)

If **yes**:
1. Record the current branch: `ORIG_BRANCH=$(git branch --show-current)`.
   If in detached HEAD, ask the user which branch to merge back to.
2. Create a new branch: `git checkout -b sdd/<slug-from-first-task>`.
3. Store worktree metadata in `.sdd/worktree.json`:
   ```json
   { "original_branch": "main", "worktree_branch": "sdd/issue-42" }
   ```
4. All subsequent work happens on this branch.

If **no**: work on the current branch directly. Skip worktree metadata.

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

## Worktree teardown

If a worktree was created (`.sdd/worktree.json` exists):

1. Print the worktree branch name and completion status for all tasks.
2. Ask the user:
   > Merge `sdd/<branch>` back into `<original_branch>`? (y/n)
3. If **yes**:
   - `git checkout <original_branch>`
   - `git merge sdd/<branch> --no-ff -m "sdd: merge completed SDD cycle"`
   - `git branch -d sdd/<branch>`
   - `rm .sdd/worktree.json`
4. If **no**: leave the branch as-is for manual review. Tell the user
   the branch name and how to merge or discard it.
