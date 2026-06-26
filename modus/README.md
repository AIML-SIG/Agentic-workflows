# Modus

An organizational layer for running LLM agents on complex, multi-step scientific work.

Modus does not replace your agent harness — Claude Code, Codex, whatever you
already run. It wraps one. It captures the domain expertise that makes an
analysis correct, encodes it as a task library, and drives a fresh agent
instance through each task until the whole workflow verifiably passes.

## The four pieces

1. **Task library (`ai_docs/task_library.json`)** — the single source of truth
   for *how the work is done*. Each task carries its own domain rules and
   verification criteria. Editing this file is the primary lever for improving
   output quality; it is also where institutional knowledge lives between
   projects. At run time it is copied to `workspace/tasks.json` (the working
   copy), which the `scope` task prunes to the study's active subset.
2. **Prompt protocol (`ai_docs/prompt.md`)** — what each agent instance reads on
   spawn: pick the next eligible task, inherit state from disk, execute, verify,
   commit.
3. **Outer loop (`run.sh`)** — spawns fresh agents until every task passes.
   Harness-agnostic via `AGENT_CMD`.
4. **Examples (`examples/`)** — domain knowledge the agent loads on demand,
   organized by task category.

## How it works

Each task defines what to produce, how to verify it, which domain rules apply,
and which upstream tasks must finish first. The outer loop spawns a **fresh
agent instance per task** — no accumulated context, no cross-task error
propagation. The agent reads the progress log from prior tasks, does its one
task, writes outputs to the workspace, verifies against the task's criteria,
commits, and exits. The loop repeats until all tasks pass or it hits
`MAX_ITERATIONS`.

State lives on disk, not in a conversation:

```
project/
├── data/                  # your inputs — read-only
└── workspace/             # created per run; all outputs land here
    ├── tasks.json         # working copy; `passes` flips true as tasks complete
    ├── progress.md        # append-only log every instance reads
    ├── {task_id}/         # one folder of outputs per task
    ├── submission/        # the run's machine-readable deliverable, if the library writes one
    ├── ESCALATE.txt       # written when human judgment is needed
    └── ANALYSIS_COMPLETE.txt
```

Each task entry:

```json
{
  "task_id": "covariate_analysis",
  "category": "modeling",
  "description": "Assess whether the candidate covariates explain variability in clearance",
  "produces": "covariate_analysis_results.csv, covariate_analysis_summary.md",
  "verify": "each pre-specified candidate is tested with an effect size and a supported/rejected decision; a retained covariate is defensible beyond a univariate association",
  "rules": ["Test each candidate against a stated criterion and estimate any relationship retained rather than fixing it", "Retain a candidate only if it adds power beyond already-supported covariates and is scientifically defensible for the drug"],
  "depends_on": ["structural_model", "study_context"],
  "passes": false
}
```

When a task needs human judgment it cannot resolve, it writes `ESCALATE.txt`. In
unattended mode (the default) a second agent auto-reviews the escalation and
resumes; set `UNATTENDED=false` to halt for a person instead.

## Quick start

Modus runs on a **project directory**: a folder with a `data/` subdirectory of
read-only inputs. The loop creates a `workspace/` beside it and writes every
output there. That is the whole contract — Modus never knows or cares where the
inputs came from.

**Prerequisites.** An agent harness on `PATH` (the default is the Claude Code
CLI, `claude`; swap any other via `AGENT_CMD`). Whatever tooling your tasks need
to *run* — for the bundled pop-PK library, that means R with `nlmixr2` as the
fitting engine — lives inside the agent's reach, not in `run.sh`.

```bash
# 1. Make a project directory and drop your inputs into data/
mkdir -p my_project/data
cp /path/to/study_docs/* my_project/data/      # protocol, plan, dataset, ...

# 2. Run the loop (defaults to the Claude Code CLI)
./run.sh my_project

# 3. Read the result. On success the workspace is archived under a run label:
ls my_project/modus_run_*_workspace/
#   progress.md          append-only log of every task
#   tasks.json           the pruned graph; `passes: true` on each finished task
#   <task_id>/           per-task outputs and <task_id>_summary.md
#   submission/          submission.yaml, if the library writes one
#   ANALYSIS_COMPLETE.txt
```

Set `RUN_LABEL=my_label` to name that archive directory yourself (otherwise it
is `modus_run_<timestamp>`). While the loop runs, the live workspace is just
`my_project/workspace/`; it is renamed only when the run finishes, escalates, or
is cancelled.

The bundled `ai_docs/task_library.json` is a lean population-PK library —
`scope → study_context → data_qc → structural_model → covariate_analysis →
review → submission` — that runs end to end on a pop-PK study. The first task,
`scope`, reads the analysis plan and prunes the library to the tasks the study
actually supports; the last, `submission`, writes a machine-readable result.
Point it at a project whose `data/` holds a protocol, an analysis plan, and a
dataset and it runs as-is. To adapt Modus to your own domain, replace this
library (see *Writing your own task library* below).

## Configuration

All overridable by environment variable:

| Variable         | Default                                   | Purpose                                        |
|------------------|-------------------------------------------|------------------------------------------------|
| `AGENT_CMD`      | `claude -p --verbose --output-format stream-json --dangerously-skip-permissions` | Harness command prefix; the prompt is appended as the final argument. The skip-permissions flag is required for headless runs (no human to answer prompts) — see the safety note. |
| `TASK_LIBRARY`   | `./ai_docs/task_library.json`             | Full task library, copied into a fresh workspace as `tasks.json`. |
| `EXAMPLES_DIR`   | `./examples`                              | Domain example library the agent loads by task category. |
| `MAX_ITERATIONS` | `50`                                      | Hard cap on agent spawns.                      |
| `TASK_TIMEOUT`   | `3300`                                    | Seconds per task before timeout.               |
| `UNATTENDED`     | `true`                                    | Auto-review escalations vs. halt for a human.  |

Swap harnesses without touching the loop:

```bash
# Drive Codex instead of Claude Code
AGENT_CMD='codex exec' ./run.sh my_project
```

## Writing your own task library

`ai_docs/task_library.json` is the whole game. To adapt Modus to a domain:

1. Decompose the workflow into tasks small enough that a fresh agent can finish
   one in a single session.
2. For each task write tight `rules` (the domain conventions a generic agent
   would otherwise get wrong) and `verify` criteria (objective, checkable —
   "row count equals N", not "looks reasonable").
3. Wire `depends_on` so each task's inputs are produced upstream.
4. Drop reference scripts into `examples/{category}/` and list them in that
   category's `index.md`. The agent loads them when it runs a matching task.


## A note on safety

`run.sh` executes agent-generated code with full filesystem access and no
approval prompts. Review your task library and run script before use, and run in
a sandboxed environment with restricted permissions for anything that matters.

## License

MIT
