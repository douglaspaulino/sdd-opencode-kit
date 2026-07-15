---
name: sdd-pipeline
description: Use ONLY when executing the /sdd command to process task files through a mandatory 5-step SDD pipeline. Defines pipeline contract, state schema, step order, transition rules, and subagent roles.
---

# SDD Pipeline Contract

This skill defines the mandatory Spec-Driven Development pipeline used by
the `/sdd` command. Every task goes through exactly 5 steps in strict
order:

    implementer → task-reviewer → fixer → code-reviewer → verifier

No step may be skipped. The fixer always runs — even when reviewers
approve (it confirms the conclusion). Reviewers and the verifier cannot
edit code (enforced at the permission level, not prompt level).

## State file

Each task has a run directory at `.sdd/runs/<task-id>/` containing:

```
.sdd/runs/<task-id>/
├── state.json
├── implementer-report.md
├── task-review.md
├── fixer-report.md
├── code-review.md
└── verifier-report.md
```

The **task-id** is derived from the task filename: lowercase,
path-safe characters only, hyphen-separated.

### state.json schema

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

## Step execution rules

### General rules

1. Steps execute in sequential order. Never parallelize.
2. Before running a step, set its status to `in_progress` and set
   `started_at`. After completion, set status to `completed` (or
   `failed`) and set `finished_at`. Write the step report to the
   specified path.
3. Every step receives as context:
   - The full content of the original task file
   - The reports of all previously completed steps
   - The current attempt number
4. Update `state.json` after EVERY step. Never batch.
5. Update `updated_at` on every state change.
6. After each step, update the task-level `status`:
   - `in_progress` while any step is pending or running
   - `completed` when verifier passes
   - `failed` when max attempts exhausted with verifier failing

### Step 1: implementer

- Subagent: `sdd-implementer`
- Purpose: write code to satisfy the task specification
- Report path: `.sdd/runs/<task-id>/implementer-report.md`

### Step 2: task-reviewer

- Subagent: `sdd-task-reviewer`
- Purpose: verify implementation matches task specification
- Report path: `.sdd/runs/<task-id>/task-review.md`
- `verdict` field: must be `approved` or `changes_requested`
- Cannot edit code (permission enforced)

### Step 3: fixer

- Subagent: `sdd-fixer`
- Purpose: apply reviewer feedback
- Report path: `.sdd/runs/<task-id>/fixer-report.md`
- Always runs — even when both reviewers approved. If approved with no
  issues, fixer confirms and reports "nothing to fix — approved as-is"

### Step 4: code-reviewer

- Subagent: `sdd-code-reviewer`
- Purpose: review code quality, bugs, style, architecture
- Report path: `.sdd/runs/<task-id>/code-review.md`
- `verdict` field: must be `approved` or `changes_requested`
- Cannot edit code (permission enforced)

### Step 5: verifier

- Subagent: `sdd-verifier`
- Purpose: run tests, build, lint; final pass/fail
- Report path: `.sdd/runs/<task-id>/verifier-report.md`
- `verdict` field: must be `pass` or `fail`
- Cannot edit code (permission enforced)
- Has bash access to run tests and build commands

## Verifier reject loop

If the verifier verdict is `fail` and `attempts < max_attempts` (3):

1. Increment `attempts` by 1
2. Reset the following steps to `pending`: fixer, code-reviewer, verifier
3. Pass the verifier report as additional context to the fixer
4. Re-run fixer → code-reviewer → verifier in order

If `attempts >= max_attempts` with verifier still `fail`:
- Mark the task `status` as `failed`
- Do NOT retry further
- Move to the next task

## Subagent context

When invoking subagents via the Task tool, always pass:

- The full task file content (read via Read tool first)
- All prior step report contents (read via Read tool first)
- Clear instructions on expected output paths and required fields

Each subagent writes its own report using the Write tool to the path
specified by the orchestrator.
