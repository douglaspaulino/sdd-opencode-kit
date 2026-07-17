---
description: Generates an HTML execution report from SDD pipeline state files.
---

Load the sdd-pipeline skill first.

## /sdd-report

Generate an HTML report from all completed `.sdd/runs/*/state.json` files.

1. Run the report generator:
   ```
   bash ~/.config/opencode/skills/sdd-pipeline/sdd-report.sh .sdd/runs .sdd/report.html
   ```

2. After generation, open the report:
   ```
   bash ~/.config/opencode/skills/sdd-pipeline/sdd-report.sh .sdd/runs .sdd/report.html --open
   ```

3. Tell the user the report path and key stats: number of tasks, total cost,
   pass/fail counts, and which models were used.
