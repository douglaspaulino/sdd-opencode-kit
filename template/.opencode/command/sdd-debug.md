---
description: Systematic debug and fix command — dispatches the sdd-debugger subagent to diagnose a problem, find the root cause, apply the fix, and record knowledge for AGENTS.md.
---

Load the sdd-debugging skill first.

## /sdd-debug <problem>

$ARGUMENTS = a description of the bug, error, or unexpected behavior. If no description provided, ask the user what's broken.

## Setup

1. Derive a slug: lowercase, hyphens, max 40 chars. Use the most distinctive part of the error or symptom.
2. Create `debug/<slug>/` directory.
3. Create `debug/<slug>/state.json`:

```json
{
  "slug": "<slug>",
  "problem": "<user's description>",
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
- The expected report path: `debug/<slug>/knowledge.md`
- The state.json path: `debug/<slug>/state.json`

## After dispatch

Read `debug/<slug>/knowledge.md`. Read `debug/<slug>/state.json`.

Update `state.json` status to `completed`.

Tell the user:

- The slug and path to `knowledge.md`
- Bugs found and fixed count
- Each bug's root cause and AGENTS.md entry (verbatim, ready for copy-paste)
