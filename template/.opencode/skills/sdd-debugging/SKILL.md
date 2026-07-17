---
name: sdd-debugging
description: Systematic debugging process for hard bugs, failing tests, unexpected behavior, broken builds, or performance regressions. Use when the user asks to "debug", "diagnose", or "investigate" something broken, or when the `/sdd-debug` command is invoked.
---

# Systematic Debugging

```
NO FIX WITHOUT: (1) a feedback loop that goes red on this bug, and (2) the root cause identified.
```

## When to use

- Hard bugs, failing tests, unexpected behavior, performance regressions
- "One quick fix" seems obvious (it rarely is)
- You've already tried 2+ fixes without success
- The previous fix didn't work
- Don't skip just because the bug "seems simple"

## Phase 1 — Build a feedback loop

**Most important phase.** One command, red-capable, deterministic, fast, unattended.

Ways to build one (preference order):
1. Failing test at the seam closest to the bug
2. Curl/HTTP script against a running dev server
3. CLI invocation with fixed input, diff against known-good
4. Headless browser script (Playwright/Puppeteer)
5. Replay a captured trace
6. Throwaway harness (minimal subsystem + mocked deps)
7. Property/fuzz loop (random inputs, find failure pattern)
8. Bisection harness (`git bisect run`)
9. Differential loop (old vs new output)
10. HITL script (human in the loop — last resort)

**Tighten the loop**: make it faster, sharper, more deterministic.

**Non-deterministic bugs**: loop the trigger 100x, parallelize, add stress. Goal is higher reproduction rate, not clean repro.

**Can't build a loop?** Stop and say so. Don't proceed without one.

Done when: one command, already run, red on the exact symptom, under 30s.

## Phase 2 — Reproduce and minimize

Run the loop. Confirm it goes red on the **exact symptom** described.

Shrink the repro: cut inputs, callers, config, data one at a time. Re-run after each cut. Keep only what's load-bearing.

Done when: every remaining element is load-bearing — removing any makes it green.

## Phase 3 — Investigate the root cause

Gather evidence before forming hypotheses:

- **Read error messages carefully.** Stack trace, line numbers, error codes.
- **Check recent changes.** `git diff`, `git log`, new deps, config changes.
- **Multi-component?** Instrument each boundary. Log what enters and exits. Find WHERE it breaks.
- **Trace the bad value backward.** Where did it originate? Keep tracing up.
- **Compare against a working example.** List every difference.

## Phase 4 — Generate hypotheses

**3–5 ranked hypotheses** before testing any. Each must be falsifiable:

> "If X is the cause, then doing Y should make the bug disappear / get worse."

**Show the list to the user before testing.** They have context you don't.

## Phase 5 — Test hypotheses / instrument

One variable at a time. Tool preference:
1. Debugger/REPL
2. Targeted logs at boundaries
3. Never "log everything and grep later"

Tag every debug log with `[DEBUG-xxxx]` — cleanup is a single grep.

After each probe: confirmed? → Phase 6. Not confirmed? → New hypothesis.

**Performance regressions**: measure first (timing harness, profiler, query plan), fix second.

## Phase 6 — Fix and write a regression test

1. Turn minimized repro into a failing test (only if a correct seam exists)
2. Watch it fail
3. Apply the fix
4. Watch it pass
5. Re-run the Phase 1 loop on the original scenario

**No correct seam exists?** That's a finding — the architecture prevents locking this bug down. Note it.

**Fix doesn't work?**
- < 3 attempts: go back to Phase 3 with new information
- ≥ 3 attempts: stop and question the architecture — wrong design, not wrong hypothesis

## Phase 7 — Cleanup and post-mortem

- [ ] Original repro no longer reproduces
- [ ] Regression test passes (or absence of seam documented)
- [ ] All `[DEBUG-xxxx]` instrumentation removed (`grep` the prefix)
- [ ] Throwaway prototypes deleted or clearly marked
- [ ] Root cause recorded in commit/PR message
- [ ] Knowledge report generated (see below)

## Bug tracking in state.json

Each bug discovered during debugging is registered as a step under `bugs` in `state.json`. The schema:

```json
"bugs": {
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
}
```

Update each bug's entry immediately upon discovery, after root cause is found, and after fix is applied. Bugs marked `deferred` are acknowledged but intentionally left for later.

## Knowledge report

After every debug session, generate a minimal markdown report at
`.sdd/runs/<RUNS_SUBPATH>/debug/<slug>/knowledge.md`.
One section per bug found, ordered by discovery:

```markdown
# Debug session: <slug>

## Bug: <bug-id> — <one-line summary>
- **Root cause:** <1-2 lines>
- **Fix:** <1-2 lines>
- **Prevention:** <1 line>
- **Test:** <path or 'no seam'>
- **AGENTS.md:** <2-4 lines>
```

Repeat for each bug. The entire report must fit in a few screens — no filler. Every AGENTS.md entry is written ready for copy-paste.

## Directory structure

```
.sdd/runs/<RUNS_SUBPATH>/
├── <task-id>/              # SDD task runs (from /sdd)
├── ...
└── debug/
    └── <slug>/
        ├── state.json      # Phase tracking + bugs ledger
        ├── repro.sh        # The feedback loop script
        └── knowledge.md    # Final report (one section per bug)
```

## Red flags — stop and go back

- "Quick fix now, investigate later"
- "Let me just try changing X and see if it works"
- "I'll change several things at once"
- "Skip the test, I'll verify by hand"
- "It's probably X, let me fix that"
- "I don't fully understand it, but this might work"
- "One more fix attempt" (after 2+ failures)
- "Here are the main problems: [lists fixes without investigating]"

Any of these → stop, go back to Phase 1 or Phase 3.
