---
description: Quickfix command — dispatches the sdd-quickfix subagent to apply a targeted fix with minimal process, recording knowledge for AGENTS.md.
---

Load the sdd-debugging skill first.

## /sdd-quickfix <problem>

$ARGUMENTS = a description of the issue or needed fix. If no description
provided, ask the user what needs fixing.

## Determine runs subpath

Same logic as `/sdd-debug`: use the single subdirectory under `.sdd/runs/`,
or `.sdd/branch.json` slug, or ask the user.

All artifacts go under `.sdd/runs/<RUNS_SUBPATH>/debug/<slug>/`.

## Setup

1. Derive a slug: lowercase, hyphens, max 40 chars. Use the most
   distinctive part of the issue.
2. Create `.sdd/runs/<RUNS_SUBPATH>/debug/<slug>/` directory.
3. Create `.sdd/runs/<RUNS_SUBPATH>/debug/<slug>/state.json`:

```json
{
  "slug": "<slug>",
  "problem": "<user's description>",
  "repos": ["."],
  "status": "in_progress",
  "started_at": "<ISO 8601>",
  "phases": { "analyze": "pending", "fix": "pending", "verify": "pending" },
  "bugs": {}
}
```

## Dispatch

Dispatch the `sdd-quickfix` subagent via the Task tool.

Pass:
- The problem description
- The slug
- The `RUNS_SUBPATH`
- The expected report path: `.sdd/runs/<RUNS_SUBPATH>/debug/<slug>/knowledge.md`
- The state.json path: `.sdd/runs/<RUNS_SUBPATH>/debug/<slug>/state.json`

## After dispatch

Read the knowledge.md and state.json. Update state.json status to
`completed`.

Tell the user:
- The slug and path to `knowledge.md`
- What was changed (one line)
- Test result
- AGENTS.md entry (verbatim, ready for copy-paste)
