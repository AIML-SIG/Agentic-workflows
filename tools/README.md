# Agentic pharmacometrics: workflow + benchmark

Two tools that fit together. A workflow drives an agent through a
pharmacometric analysis; a benchmark scores what it produces against a synthetic
study with known ground truth.

| Folder | What it is |
|--------|------------|
| [`modus/`](modus/) | The **workflow**. Wraps an agent harness (Claude Code, Codex, …) and drives fresh agent instances through a task library until the work verifiably passes. |
| [`pharmbench/`](pharmbench/) | The **benchmark**. Ships synthetic scenarios (a visible question packet + a sealed answer key + traps) and a scorer. Tool-agnostic: it scores *any* workflow that reads a `data/` packet and writes a `submission.yaml`. |

They meet at exactly one artifact — `submission.yaml` — and one rule: **design is
visible, results are held out**.

## 60-second feel for each

**Score a submission** (benchmark only, no agent needed):

```sh
cd pharmbench
Rscript score.R --truth scenarios/mab-poppk-v0/evals/truth.yaml \
  scenarios/mab-poppk-v0/evals/submission.example.yaml
```

Prints a scorecard for a deliberately imperfect submission (overall ≈ 0.71) so
you see the traps biting.

**Run the full loop** (workflow + benchmark): see
[`pharmbench/README.md`](pharmbench/README.md) → *Quickstart: the full benchmark
loop* (proctor → run → score). To adapt the workflow to your own domain, see
[`modus/README.md`](modus/README.md) → *Writing your own task library*.

## Prerequisites

The combined set across both tools:

- **An agent harness** on `PATH` — the Claude Code CLI (`claude`) by default, or
  any CLI via `AGENT_CMD` (e.g. `codex exec`). Needed only to *run* the workflow,
  not to score.
- **R** (tested 4.3.3) with `mrgsolve` (data generation; needs a C toolchain such
  as gcc) and `yaml` (scoring): `install.packages(c("mrgsolve", "yaml"))`.
- **Python 3** with `pyyaml`, only for the optional results visualizer:
  `pip install pyyaml`.

## License

MIT (both folders). See each folder's `LICENSE`.
