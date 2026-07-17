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

- **Branch lifecycle.** At `/sdd` start, ask the user whether to create
  a new branch for the run. If yes: record the original branch in
  `.sdd/branch.json`, create `sdd/<slug>`, and work there. After all
  tasks complete, ask whether to merge back with `--no-ff`. If declined,
  leave the branch for manual review.

- **CONTEXT.md.** If `CONTEXT.md` exists at the project root, include its
  path in every subagent dispatch. It maps project jargon to short terms
  and keeps code and reviews concise.

- **CRITICAL — cost tracking.** The fields `cost_usd`, `model`,
  `executions`, and `session_id` exist ONLY inside `steps.<step>`.
  They must NEVER appear at the top level of state.json. **Never set
  these fields manually.** After every step returns, run the
  `sdd-cost.sh` script — it queries the database and writes all four
  fields to the correct step. The script also populates `started_at`
  and `finished_at` with actual ISO 8601 timestamps from the session.

## State file

Each task lives at `.sdd/runs/<runs-subpath>/<task-id>/`. The
`runs-subpath` is derived from the `/sdd` argument (see command/sdd.md).

```
.sdd/runs/<runs-subpath>/<task-id>/
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
      "executions": 0,
      "cost_usd": 0.0,
      "model": "",
      "session_id": "",
      "started_at": "ISO 8601",
      "finished_at": "ISO 8601"
    },
    "task-reviewer": {
      "status": "pending | in_progress | completed | failed",
      "report": "task-review.md",
      "verdict": "approved | changes_requested",
      "executions": 0,
      "cost_usd": 0.0,
      "model": "",
      "session_id": "",
      "started_at": "ISO 8601",
      "finished_at": "ISO 8601"
    },
    "fixer": {
      "status": "pending | in_progress | completed | failed",
      "report": "fixer-report.md",
      "executions": 0,
      "cost_usd": 0.0,
      "model": "",
      "session_id": "",
      "started_at": "ISO 8601",
      "finished_at": "ISO 8601"
    },
    "code-reviewer": {
      "status": "pending | in_progress | completed | failed",
      "report": "code-review.md",
      "verdict": "approved | changes_requested",
      "executions": 0,
      "cost_usd": 0.0,
      "model": "",
      "session_id": "",
      "started_at": "ISO 8601",
      "finished_at": "ISO 8601"
    },
    "verifier": {
      "status": "pending | in_progress | completed | failed",
      "report": "verifier-report.md",
      "verdict": "pass | fail",
      "executions": 0,
      "cost_usd": 0.0,
      "model": "",
      "session_id": "",
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
   Use actual ISO 8601 timestamps (current time); these will be
   overwritten with session-level timestamps by `sdd-cost.sh` after
   the step returns.
3. Each step receives: task file path, prior report paths, attempt
   number, current step execution count, CONTEXT.md path (if exists).
4. Before dispatching a step: increment `executions` in state.json for that
   step. Never reset `executions` — it is cumulative across retries.
5. **CRITICAL — after each step returns:** extract the session ID
   (`task_id`) from the Task tool result and run:
   ```
   bash ~/.config/opencode/skills/sdd-pipeline/sdd-cost.sh .sdd/runs/<runs-subpath>/<task-id>/state.json <step> <session-id>
   ```
   The script queries the opencode database and writes to
   `steps.<step>.cost_usd` (cumulative sum), `steps.<step>.model`,
   `steps.<step>.session_id`, `steps.<step>.started_at`, and
   `steps.<step>.finished_at`. **Never set cost_usd, model,
   session_id manually. Never write them at state top-level.**
   The script must run after EVERY step — no exceptions.
6. Update `state.json` after EVERY step. Never batch.
7. Update `updated_at` on every state change.
8. **After the verifier returns `"verdict": "pass"`, the controller MUST
   set task-level `status` to `"completed"`** and update `updated_at`.
   If `attempts >= max_attempts` and verifier is still `fail`, set
   task-level `status` to `"failed"`.

### Step 1: implementer

- Subagent: `sdd-implementer`
- Report: `.sdd/runs/<runs-subpath>/<task-id>/implementer-report.md`
- Status codes: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
- **TDD is mandatory.** The implementer works in RED → GREEN cycles.
  The report must include RED + GREEN evidence for every feature. The
  task-reviewer and code-reviewer verify this.
- If BLOCKED/NEEDS_CONTEXT: resolve and re-dispatch.

### Step 2: task-reviewer

- Subagent: `sdd-task-reviewer`
- Report: `.sdd/runs/<runs-subpath>/<task-id>/task-review.md`
- Verdict: `approved` | `changes_requested`
- Checks: spec compliance, TDD evidence, standards. Three axes.

### Step 3: fixer

- Subagent: `sdd-fixer`
- Report: `.sdd/runs/<runs-subpath>/<task-id>/fixer-report.md`
- Always runs. If approved with no issues, confirms.

### Step 4: code-reviewer

- Subagent: `sdd-code-reviewer`
- Report: `.sdd/runs/<runs-subpath>/<task-id>/code-review.md`
- Verdict: `approved` | `changes_requested`
- Checks: code quality, test quality, standards, YAGNI scope, Fowler smells.
  Five axes.

### Step 5: verifier

- Subagent: `sdd-verifier`
- Report: `.sdd/runs/<runs-subpath>/<task-id>/verifier-report.md`
- Verdict: `pass` | `fail`

## Verifier reject loop

If `fail` and `attempts < max_attempts` (3):

1. Increment `attempts`
2. Reset fixer, code-reviewer, verifier status to `pending` (preserve
   their `executions`, `cost_usd`, `model`, and `session_id` — never
   zero them out)
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
- Current step execution count (from `steps.<step>.executions`)
- Expected report path

Each subagent writes its own report. Reports are handoff — the next
subagent reads them as files.

## Report generation

After all tasks complete (or at any time), generate an HTML report:

```
bash ~/.config/opencode/skills/sdd-pipeline/sdd-report.sh .sdd/runs .sdd/report.html
```

Use `--open` to auto-open in the browser after generation. The report
includes: summary dashboard, per-task breakdowns with cost/model/duration,
consolidated findings analysis, and AGENTS.md improvement suggestions.

The `/sdd-report` command does this automatically.

For the controller: when all tasks in the run are complete, run this
script and tell the user the report path and a 1-line summary.
