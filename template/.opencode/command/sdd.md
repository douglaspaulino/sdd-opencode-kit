---
description: Runs the mandatory SDD pipeline on task files.
---

Load the sdd-pipeline skill first.

## Resolve tasks

$ARGUMENTS = single file or directory.
- File: one task.
- Directory: glob `$ARGUMENTS/*.md`, sorted alphabetically.
- No tasks → tell user, stop.

Derive `RUNS_SUBPATH`: strip leading `.scratch/` prefix from
$ARGUMENTS, then strip any trailing filename to keep only the
directory portion. If no `.scratch/` prefix, use the full relative
directory path. Examples:
  `.scratch/renda-fixa-foundation/issues/` → `renda-fixa-foundation/issues`
  `.scratch/proj/tasks/issue-42.md`       → `proj/tasks`
  `my-tasks/`                             → `my-tasks`
Use `.sdd/runs/<runs-subpath>/<task-id>/` for all run artifacts.

## Branch setup

Before any task execution, read all task files to collect the
`## Repositories` section. For each task, parse the list of repos:

```
## Repositories
- ../project-x (main)
- ../project-b (develop)
```

If a task has no `## Repositories` section, it uses `["."]` (current repo
only). Collect all unique repos with their base branches.

Ask the user:

> Create branches for this SDD run across all affected repos? (y/n)

If **yes**:
1. Derive the slug from the first task filename.
2. For each unique repo:
   - `cd <repo_path>`
   - Record `ORIG_BRANCH=$(git branch --show-current)`. If detached HEAD,
     ask the user which branch to merge back to.
   - `git checkout -b sdd/<slug>`.
3. Store metadata in `.sdd/branch.json`:
   ```json
   {
     "slug": "<slug>",
     "branches": [
       { "repo": ".", "repo_path": "/abs/path", "original_branch": "main", "sdd_branch": "sdd/<slug>" },
       { "repo": "../project-x", "repo_path": "/abs/path/project-x", "original_branch": "main", "sdd_branch": "sdd/<slug>" }
     ]
   }
   ```

If **no**: work on current branches directly. Skip branch metadata.

## Pre-flight

If `CONTEXT.md` exists at the project root, note its path for every
subagent dispatch. If `.sdd/ledger.md` exists, read it — tasks marked
complete are done, do not re-dispatch them.

## Phase 1 — Parallel implementers

For every pending task: create fresh state.json (if none exists),
mark implementer `in_progress`, increment `executions`.

Dispatch ALL implementers in a SINGLE message using multiple Task tool
calls (one per task, `sdd-implementer`). This is the biggest latency win
— implementers for independent tasks run concurrently.

Pass each: task file path + CONTEXT.md path (if any) + expected report
path + `repos` array from the task's `## Repositories` section (or `["."]`
if absent) + the `slug` from `.sdd/branch.json` (or a generated slug).

After ALL implementers return: run `sdd-cost.sh` for each, update
state.json (read the `repos` field from each task's state.json — the
implementer may have expanded it), write reports. If any returned
BLOCKED/NEEDS_CONTEXT, resolve and re-dispatch that task's implementer
separately.

## Phase 2 — Per-task remaining steps

For each task (in original sorted order), run steps 2–5 sequentially:

### Step 2: task-reviewer

Dispatch `sdd-task-reviewer`. Pass task file + implementer report +
CONTEXT.md. Run `sdd-cost.sh` after return. Read verdict from report.

### Step 3: fixer (CONDITIONAL)

**If task-reviewer verdict is `approved`:**
- Set fixer status to `skipped`, set `skip_reason` to
  `"approved — no changes needed by task-reviewer"`.
- Skip to code-reviewer. Do NOT dispatch the fixer subagent.
- Do NOT run `sdd-cost.sh` for fixer — leave cost_usd at 0.0.

**If task-reviewer verdict is `changes_requested`:**
- Dispatch `sdd-fixer`. Pass task file + implementer report +
  task-review report + CONTEXT.md. Run `sdd-cost.sh` after return.

### Step 4: code-reviewer

Dispatch `sdd-code-reviewer`. Pass task file + all prior reports +
CONTEXT.md. Run `sdd-cost.sh` after return.

### Step 5: verifier

Dispatch `sdd-verifier`. Pass task file + all prior reports +
attempt number + max attempts. Run `sdd-cost.sh` after return.

Read verdict.

### Verifier reject loop

If `fail` and `attempts < max_attempts` (3):
1. Increment `attempts`
2. Reset fixer, code-reviewer, verifier status to `pending` (preserve
   `executions`, `cost_usd`, `model`, `session_id` — never zero them)
3. Pass verifier report to fixer as additional context
4. Re-run fixer → code-reviewer → verifier

If `attempts >= max_attempts` with verifier `fail`:
- Mark task `failed`, next task.

If `pass`: mark task `completed`, append to `.sdd/ledger.md`, next task.

## Summary

Print table: task file, final status, step of failure (if any), attempts,
total cost USD (sum of all `steps.<step>.cost_usd`).

## Branch teardown

If branches were created (`.sdd/branch.json` exists):

1. Print the branch name and completion status for all tasks.

2. For each branch entry in `.sdd/branch.json`, ask the user:
   > Merge `sdd/<slug>` in `<repo>` back into `<original_branch>`? (y/n)

   If **yes**:
   - `cd <repo_path>`
   - `git checkout <original_branch>`
   - `git merge sdd/<slug> --no-ff -m "sdd: merge completed SDD cycle"`
   - `git branch -d sdd/<slug>`

   If **no**: tell the user the repo path, branch name, and how to merge
   or discard it manually.

3. After all repos processed: `rm .sdd/branch.json`.
