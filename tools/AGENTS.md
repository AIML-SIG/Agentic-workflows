# Notes for an agent bootstrapping this repo

You are likely here because a user pointed you at this repo and asked you to get
it running. This file is the orientation; the per-folder READMEs are the detail.

## What's here

- `modus/` — a **workflow**: drives fresh agent instances through a task library
  (`modus/ai_docs/task_library.json`) via `modus/run.sh`. Harness-agnostic.
- `pharmbench/` — a **benchmark**: scores a workflow's `submission.yaml` against a
  held-out answer key. Tool-agnostic — it scores any workflow, not just modus.

The contract between them is one file: a workflow reads a `data/` packet and
writes `workspace/submission/submission.yaml`; the benchmark scores that.

## Bring up the environment first (this is the usual blocker)

Verify, and install what's missing, before running anything:

1. **Agent harness** — needed only to *run* the workflow. `claude` (Claude Code
   CLI) is the default; `codex` works via `AGENT_CMD='codex exec'`. Check it is on
   `PATH`.
2. **R** with `mrgsolve`, `yaml`, and `nlmixr2`. `mrgsolve` compiles an ODE
   model (data generation), so a C toolchain (gcc) must be present. `nlmixr2`
   is the fitting engine the workflow tasks use at run time. Install:
   `Rscript -e 'install.packages(c("mrgsolve","yaml","nlmixr2"))'`. Confirm
   with `Rscript -e 'library(nlmixr2)'`.
3. **Python 3 + pyyaml** — only for the optional `pharmbench/visualize_results.py`.

## Then run, in this order

1. **Score-only smoke test** (no agent, proves R + scorer work):
   `cd pharmbench && Rscript score.R --truth
   scenarios/mab-poppk-v0/evals/truth.yaml
   scenarios/mab-poppk-v0/evals/submission.example.yaml` → expect overall ≈ 0.71.
2. **Full loop** — follow `pharmbench/README.md` → *Quickstart: the full benchmark
   loop*: `proctor.sh` stages the scenario into a fresh project dir outside the
   repo (this copy is the blinding — never run the workflow in-place against the
   pharmbench tree), then `modus/run.sh` runs the workflow, then `score.R` grades
   it from outside the loop.

## Two things not to get wrong

- **Blinding.** `pharmbench/evals/` and `build/` are held out — never copy them
  into a workflow's working directory, and never run a workflow in-place inside
  `pharmbench/`. Only `scenario/*` travels. The proctor enforces this; don't
  bypass it.
- **No leakage into the workflow.** A scenario's specific answers (which covariate
  is a decoy, which records are corrupted) must never be written into
  `modus/ai_docs/task_library.json` or anything the runtime loads. Rules stay at
  general-competence altitude. See `modus/ai_docs/plan.md`, "A note on leakage".

Beyond that, the per-folder READMEs and `plan.md` files are the source of truth.
