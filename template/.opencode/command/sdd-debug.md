---
description: Systematic debug and fix command — dispatches the sdd-debugger subagent to diagnose a problem, find the root cause, apply the fix, and record knowledge for AGENTS.md.
---

Load the sdd-debugging skill first.

## /sdd-debug <problem>

$ARGUMENTS = a description of the bug, error, or unexpected behavior. If no description provided, ask the user what's broken.

## Determine runs subpath

Determine `RUNS_SUBPATH` — the project context for storing debug artifacts
alongside SDD task runs:

1. If `.sdd/runs/` has exactly one subdirectory (e.g. `renda-fixa-foundation`),
   use it as `RUNS_SUBPATH`.
2. Otherwise, if `.sdd/branch.json` exists, read the `sdd_branch` field
   (format `sdd/<slug>`) — the slug is the `RUNS_SUBPATH`.
3. Otherwise, ask the user: "What is the runs subpath for this debug
   session? (e.g. `renda-fixa-foundation`)".

All artifacts go under `.sdd/runs/<RUNS_SUBPATH>/debug/<slug>/`.

## Setup

1. Derive a slug: lowercase, hyphens, max 40 chars. Use the most distinctive part of the error or symptom.
2. Create `.sdd/runs/<RUNS_SUBPATH>/debug/<slug>/` directory.
3. Create `.sdd/runs/<RUNS_SUBPATH>/debug/<slug>/state.json`:

```json
{
  "runs_subpath": "<RUNS_SUBPATH>",
  "slug": "<slug>",
  "problem": "<user's description>",
  "repos": ["."],
  "phase": 1,
  "status": "in_progress",
  "started_at": "<ISO 8601>",
  "updated_at": "<ISO 8601>",
  "phases": {
    "1_feedback_loop": { "status": "in_progress" },
    "2_reproduce_minimize": { "status": "pending" },
    "3_root_cause": { "status": "pending" },
    "4_hypotheses": { "status": "pending" },
    "5_test_hypotheses": { "status": "pending" },
    "6_fix_regression_test": { "status": "pending" },
    "7_cleanup": { "status": "pending" }
  },
  "bugs": {}
}
```

bug schema:

```json
"<bug-id>": {
  "status": "found | investigating | fixed | deferred",
  "description": "<one-line>",
  "root_cause": "<discovered root cause>",
  "fix": "<applied fix>",
  "regression_test": "<path or 'no seam'>",
  "knowledge_entry": "<AGENTS.md snippet>",
  "found_at": "<ISO 8601>",
  "fixed_at": "<ISO 8601>"
}
```

## Dispatch

Dispatch the `sdd-debugger` subagent via the Task tool.

Pass:
- The problem description
- The slug
- The `RUNS_SUBPATH`
- The expected report path: `.sdd/runs/<RUNS_SUBPATH>/debug/<slug>/knowledge.md`
- The state.json path: `.sdd/runs/<RUNS_SUBPATH>/debug/<slug>/state.json`

## After dispatch

Read `.sdd/runs/<RUNS_SUBPATH>/debug/<slug>/knowledge.md`.
Read `.sdd/runs/<RUNS_SUBPATH>/debug/<slug>/state.json`.

Update `state.json` status to `completed`.

Tell the user:

- The slug and path to `knowledge.md`
- Bugs found and fixed count
- Each bug's root cause and AGENTS.md entry (verbatim, ready for copy-paste)
