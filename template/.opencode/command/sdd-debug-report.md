---
description: Generates an HTML debug report from sdd-debug session state files.
---

Load the sdd-debugging skill first.

## /sdd-debug-report

Generate an HTML report from all completed `.sdd/runs/*/debug/*/state.json` files.

1. Run the report generator:
   ```
   bash ~/.config/opencode/skills/sdd-debugging/sdd-debug-report.sh .sdd/runs .sdd/debug-report.html
   ```

2. After generation, open the report:
   ```
   bash ~/.config/opencode/skills/sdd-debugging/sdd-debug-report.sh .sdd/runs .sdd/debug-report.html --open
   ```

3. Tell the user the report path and key stats: number of debug sessions,
   bugs found, fixed/deferred counts, and suggested AGENTS.md entries.
