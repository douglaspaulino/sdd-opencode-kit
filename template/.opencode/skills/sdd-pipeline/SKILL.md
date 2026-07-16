---
name: sdd-pipeline
description: Use ONLY when executing the /sdd command to process task files through a mandatory 5-step SDD pipeline. Defines pipeline contract, state schema, step order, transition rules, and subagent roles.
---

# SDD Pipeline

Mandatory 5-step pipeline:

    implementer → task-reviewer → fixer → code-reviewer → verifier

No step may be skipped. Fixer always runs. Reviewers and verifier cannot
edit code (permission-enforced, not prompt-level).

## Controller discipline

- **Narrate at most one short line between tool calls.** Tool results
  carry the record.
- **Continuous execution.** Do not stop between tasks to check in.
  Execute all tasks without pausing. Stop only for: BLOCKED, ambiguity
  that prevents progress, or all tasks complete.
- **File handoffs.** Pass task content and prior reports as file paths,
  never as pasted text. Your context stays lean; subagents read what they
  need.
- **Progress ledger.** Before starting and after each task, write a line
  to `.sdd/ledger.md`:

  ```
  Task <task-id>: <status> (<short SHA>..<short SHA>)
  ```

  The ledger survives compaction. After a compact, trust the ledger and
  `git log` over your own recollection. Never re-execute a task the
  ledger marks complete.

- **CONTEXT.md.** If `CONTEXT.md` exists at the project root, include its
  path in every subagent dispatch. It maps project jargon to short terms
  and keeps code and reviews concise.

## State file

Each task: `.sdd/runs/<task-id>/`:

```
.sdd/runs/<task-id>/
├── state.json
├── implementer-report.md
├── task-review.md
├── fixer-report.md
├── code-review.md
└── verifier-report.md
```

`task-id` = filename, lowercase, hyphens, path-safe.

### state.json

```json
{
  "task_file": "tasks/issue-42.md",
  "status": "in_progress | completed | failed",
  "attempts": 1,
  "max_attempts": 3,
  "created_at": "ISO 8601",
  "updated_at": "ISO 8601",
  "steps": {
    "implementer": {
      "status": "pending | in_progress | completed | failed",
      "report": "implementer-report.md",
      "started_at": "ISO 8601",
      "finished_at": "ISO 8601"
    },
    "task-reviewer": {
      "status": "pending | in_progress | completed | failed",
      "report": "task-review.md",
      "verdict": "approved | changes_requested",
      "started_at": "ISO 8601",
      "finished_at": "ISO 8601"
    },
    "fixer": {
      "status": "pending | in_progress | completed | failed",
      "report": "fixer-report.md",
      "started_at": "ISO 8601",
      "finished_at": "ISO 8601"
    },
    "code-reviewer": {
      "status": "pending | in_progress | completed | failed",
      "report": "code-review.md",
      "verdict": "approved | changes_requested",
      "started_at": "ISO 8601",
      "finished_at": "ISO 8601"
    },
    "verifier": {
      "status": "pending | in_progress | completed | failed",
      "report": "verifier-report.md",
      "verdict": "pass | fail",
      "started_at": "ISO 8601",
      "finished_at": "ISO 8601"
    }
  }
}
```

## Step execution

### General rules

1. Sequential only. Never parallelize steps.
2. Set status to `in_progress` + `started_at` before running. Set
   `completed`/`failed` + `finished_at` after. Write report.
3. Each step receives: task file path, prior report paths, attempt
   number, CONTEXT.md path (if exists).
4. Update `state.json` after EVERY step. Never batch.
5. Update `updated_at` on every state change.
6. Task-level `status`: `in_progress` while pending, `completed` on
   verifier pass, `failed` on max attempts exhausted.

### Step 1: implementer

- Subagent: `sdd-implementer`
- Report: `.sdd/runs/<task-id>/implementer-report.md`
- Status codes: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
- If BLOCKED/NEEDS_CONTEXT: resolve and re-dispatch.

### Step 2: task-reviewer

- Subagent: `sdd-task-reviewer`
- Report: `.sdd/runs/<task-id>/task-review.md`
- Verdict: `approved` | `changes_requested`

### Step 3: fixer

- Subagent: `sdd-fixer`
- Report: `.sdd/runs/<task-id>/fixer-report.md`
- Always runs. If approved with no issues, confirms.

### Step 4: code-reviewer

- Subagent: `sdd-code-reviewer`
- Report: `.sdd/runs/<task-id>/code-review.md`
- Verdict: `approved` | `changes_requested`

### Step 5: verifier

- Subagent: `sdd-verifier`
- Report: `.sdd/runs/<task-id>/verifier-report.md`
- Verdict: `pass` | `fail`

## Verifier reject loop

If `fail` and `attempts < max_attempts` (3):

1. Increment `attempts`
2. Reset fixer, code-reviewer, verifier to `pending`
3. Pass verifier report to fixer as additional context
4. Re-run fixer → code-reviewer → verifier

If `attempts >= max_attempts` with verifier `fail`:
- Mark task `failed`, move to next.

## Subagent dispatch

When using the Task tool, pass:

- Task file path
- Prior report paths (not contents)
- CONTEXT.md path (if exists)
- Current attempt number
- Expected report path

Each subagent writes its own report. Reports are handoff — the next
subagent reads them as files.
