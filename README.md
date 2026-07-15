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

```sh
./install.sh /path/to/your/repo [--track-state]
```

Copies `template/.opencode/` into the target repo (never overwrites existing
files) and adds `.sdd/runs/` to `.gitignore` (use `--track-state` to version
state instead). Restart opencode in the target repo afterwards.

## Usage

```
/sdd tasks/issue-42.md      # single task
/sdd tasks/                 # every *.md in the directory
```

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
