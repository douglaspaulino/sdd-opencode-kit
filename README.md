# sdd-opencode-kit

Spec-Driven Development (SDD) pipeline for [opencode](https://opencode.ai).
Installs a `/sdd` command into any repository that processes task/issue files
through a mandatory 5-step pipeline:

    implementer → task-reviewer → fixer → code-reviewer → verifier

Every step is enforced — reviewers cannot edit code (permission-level, not
prompt-level), the fixer always runs, and execution state is persisted per
task so interrupted runs resume exactly where they stopped.

## How it works

`/sdd <path>` accepts a single task file or a directory with N task files
(free-form markdown). For each task:

1. A run directory is created at `.sdd/runs/<task-id>/` with a `state.json`
2. Each step runs as an isolated subagent and writes a report used as
   handoff for the next step
3. `state.json` is updated after every step — re-running `/sdd` skips
   completed steps and resumes from the first pending one
4. If the verifier rejects, the pipeline loops fixer → code-reviewer →
   verifier up to 3 attempts, then marks the task `failed` and moves on

| Step | Role | Permissions |
|---|---|---|
| sdd-implementer | Implements the task | edit: allow |
| sdd-task-reviewer | Checks implementation matches the task spec | edit: deny |
| sdd-fixer | Applies review feedback (runs even if approved) | edit: allow |
| sdd-code-reviewer | Reviews code quality, bugs, style | edit: deny |
| sdd-verifier | Runs tests/build, final verdict | edit: deny, bash: allow |

## Installation

### Via npx (recommended)

> **Note:** npm v10+ requires `--allow-git` to fetch packages from GitHub.
> Run the command below **once** to allow git dependencies, then use `npx` normally:
> ```sh
> npm config set allow-git all
> ```

```sh
# Install globally (for all projects)
npx github:douglaspaulino/sdd-opencode-kit --global

# Install into a specific repository
npx github:douglaspaulino/sdd-opencode-kit /path/to/your/repo

# Install into a repository, tracking execution state in git
npx github:douglaspaulino/sdd-opencode-kit /path/to/your/repo --track-state

# Interactive mode (prompts for choices)
npx github:douglaspaulino/sdd-opencode-kit
```

**If you prefer not to configure npm**, use the `--allow-git` flag directly:

```sh
npx --allow-git all github:douglaspaulino/sdd-opencode-kit --global
npx --allow-git all github:douglaspaulino/sdd-opencode-kit /path/to/your/repo
```

### Via npm global install

```sh
npm install --allow-git all -g github:douglaspaulino/sdd-opencode-kit
sdd-install --global
sdd-install /path/to/your/repo
```

### Legacy (install.sh)

```sh
./install.sh /path/to/your/repo [--track-state]
```

All methods copy `template/.opencode/` into the target (never overwrites existing
files) and adds `.sdd/runs/` to `.gitignore` (use `--track-state` to version
state instead). Restart opencode in the target repo afterwards.

## Usage

```
/sdd tasks/issue-42.md      # single task
/sdd tasks/                 # every *.md in the directory
```

### Optional: create a CONTEXT.md

A `CONTEXT.md` file in the project root acts as a shared vocabulary for all
subagents. Map project jargon to short terms:

```md
# CONTEXT.md

- **authn** — the authentication layer (replaces "UserAuthenticationServiceFactoryProvider")
- **materialize** — giving a lesson a real spot on disk (instead of "creating file system entries for course content")
```

The implementer reads this first to produce concise, consistently-named code.
Code reviews reference these terms to avoid report verbosity.

## Customizing models

The kit ships with the **Go 3 — High volume** preset as default. Every model
is just a default — override any step in the target repo's `opencode.json`
without touching the agent files:

```json
{
  "agent": {
    "sdd-implementer":   { "model": "opencode-go/kimi-k2.7-code" },
    "sdd-code-reviewer": { "model": "opencode-go/glm-5.2" }
  }
}
```

Copy an entire preset block from below into your `opencode.json`.

### Setting model variants

For models that support reasoning-effort variants (e.g. `low`, `medium`,
`high`), you can also set the `variant` field per agent. This controls
how much compute the model spends "thinking" before responding:

```json
{
  "agent": {
    "sdd-implementer":   { "model": "opencode-go/glm-5.2",  "variant": "high" },
    "sdd-code-reviewer": { "model": "opencode-go/glm-5.2",  "variant": "high" },
    "sdd-task-reviewer": { "model": "opencode-go/glm-5.2",  "variant": "medium" },
    "sdd-fixer":         { "model": "opencode-go/glm-5.2",  "variant": "medium" },
    "sdd-verifier":      { "model": "opencode-go/glm-5.2",  "variant": "low" }
  }
}
```

| Role | Recommended variant | Why |
|---|---|---|
| implementer | `high` | Needs deep reasoning for architecture, patterns, edge cases |
| code-reviewer | `high` | Scans diff for Fowler smells, bugs, YAGNI — most complex judgment |
| task-reviewer | `medium` | Spec compliance check: structured task, less open-ended |
| fixer | `medium` | Targeted fixes with reviewer guidance — narrower scope |
| verifier | `low` | Runs tests, checks output — mechanical, not creative |

> Not all models expose variants. Check your provider's docs. Some models
> encode tier in the name itself (e.g. `qwen3.7-max`). For those, swap the
> `model` field instead of setting `variant`.

## Why different models per step

Using the same LLM across all pipeline steps invites **self-confirmation
bias** — the model tends to repeat the same reasoning errors and approve
its own work. Mixing models breaks this cycle. Each step benefits from a
different cognitive profile:

| Pillar | What it means for SDD |
|---|---|
| **Specialization** | Each model is chosen for its strength — implementation, review, reasoning, speed. |
| **Independence** | Who implements does not validate. Errors surface in review, not in self-check. |
| **Cost × Performance** | Expensive models only where judgment matters. Fast models for repetitive verification. |
| **Defense in depth** | Every step is a quality barrier before the next one. No single model is the bottleneck. |

## Model presets

### opencode go (subscription, request quotas)

Best when you pay a flat subscription. Scarce-quota models (GLM, Qwen Max,
Kimi) go to low-request judgment roles; huge-quota models (DeepSeek Flash,
MiMo) absorb high-request roles.

#### Go 1 — Max quality
| Step | Model |
|---|---|
| implementer | `opencode-go/kimi-k2.7-code` |
| task-reviewer | `opencode-go/minimax-m3` |
| fixer | `opencode-go/glm-5.2` |
| code-reviewer | `opencode-go/qwen3.7-max` |
| verifier | `opencode-go/deepseek-v4-flash` |

#### Go 2 — Balanced
| Step | Model |
|---|---|
| implementer | `opencode-go/kimi-k2.7-code` |
| task-reviewer | `opencode-go/deepseek-v4-flash` |
| fixer | `opencode-go/deepseek-v4-pro` |
| code-reviewer | `opencode-go/glm-5.2` |
| verifier | `opencode-go/mimo-v2.5` |

#### Go 3 — High volume (default)
| Step | Model |
|---|---|
| implementer | `opencode-go/deepseek-v4-pro` |
| task-reviewer | `opencode-go/mimo-v2.5` |
| fixer | `opencode-go/minimax-m2.7` |
| code-reviewer | `opencode-go/kimi-k2.6` |
| verifier | `opencode-go/deepseek-v4-flash` |

#### Go 4 — Quota saver
| Step | Model |
|---|---|
| implementer | `opencode-go/mimo-v2.5-pro` |
| task-reviewer | `opencode-go/mimo-v2.5` |
| fixer | `opencode-go/qwen3.7-plus` |
| code-reviewer | `opencode-go/deepseek-v4-pro` |
| verifier | `opencode-go/deepseek-v4-flash` |

#### Go 5 — Ladder (rigor increases toward the final gate)
| Step | Model |
|---|---|
| implementer | `opencode-go/qwen3.7-plus` |
| task-reviewer | `opencode-go/minimax-m3` |
| fixer | `opencode-go/kimi-k2.7-code` |
| code-reviewer | `opencode-go/glm-5.1` |
| verifier | `opencode-go/qwen3.7-max` |

### opencode zen (pay-per-token)

Best when you pay per token. Spend on implementer and code-reviewer (highest
leverage), keep the verifier cheap, and mix model families between
implementation and review to avoid self-approval bias.

#### Zen 1 — Max quality
| Step | Model |
|---|---|
| implementer | `opencode/claude-opus-4-8` |
| task-reviewer | `opencode/gpt-5.6-terra` |
| fixer | `opencode/claude-sonnet-5` |
| code-reviewer | `opencode/gpt-5.6-sol` |
| verifier | `opencode/claude-haiku-4-5` |

#### Zen 2 — Balanced
| Step | Model |
|---|---|
| implementer | `opencode/claude-sonnet-5` |
| task-reviewer | `opencode/gpt-5.4-mini` |
| fixer | `opencode/gpt-5.3-codex` |
| code-reviewer | `opencode/gemini-3.1-pro` |
| verifier | `opencode/gpt-5.1-codex-mini` |

#### Zen 3 — Cost-effective
| Step | Model |
|---|---|
| implementer | `opencode/kimi-k2.7-code` |
| task-reviewer | `opencode/minimax-m3` |
| fixer | `opencode/glm-5` |
| code-reviewer | `opencode/claude-haiku-4-5` |
| verifier | `opencode/deepseek-v4-flash` |

#### Zen 4 — Ultra-budget
| Step | Model |
|---|---|
| implementer | `opencode/qwen3.6-plus` |
| task-reviewer | `opencode/deepseek-v4-flash` |
| fixer | `opencode/minimax-m2.7` |
| code-reviewer | `opencode/kimi-k2.5` |
| verifier | `opencode/gpt-5-nano` |

#### Zen 5 — Free / hybrid
| Step | Model |
|---|---|
| implementer | `opencode/deepseek-v4-flash-free` |
| task-reviewer | `opencode/nemotron-3-ultra-free` |
| fixer | `opencode/north-mini-code-free` |
| code-reviewer | `opencode/claude-haiku-4-5` |
| verifier | `opencode/mimo-v2.5-free` |

## Execution state

```json
{
  "task_file": "tasks/issue-42.md",
  "status": "in_progress",
  "attempts": 1,
  "max_attempts": 3,
  "steps": {
    "implementer":   { "status": "completed", "report": "implementer-report.md" },
    "task-reviewer": { "status": "completed", "verdict": "approved" },
    "fixer":         { "status": "in_progress" },
    "code-reviewer": { "status": "pending" },
    "verifier":      { "status": "pending" }
  }
}
```

## Inspiration

This project draws from two standout agent-skills methodology repos:

| Project | Link | Key ideas adopted |
|---|---|---|
| **Matt Pocock Skills** | [mattpocock/skills](https://github.com/mattpocock/skills) | Two-axis review (Spec vs Standards), Fowler smell baseline, shared vocabulary (`CONTEXT.md`), leading words, completion criteria, pruning discipline |
| **Superpowers (obra)** | [obra/superpowers](https://github.com/obra/superpowers) | Subagent-driven-development, file handoffs (never paste text), progress ledger (survives compaction), YAGNI enforcement, escalation rules (BLOCKED/NEEDS_CONTEXT), self-review checklist, "follow don't explore" principle |
