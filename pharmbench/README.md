# PMbench

A benchmark that scores an agentic pharmacometrics workflow against a synthetic
study with **known ground truth**. Every known failure mode is encoded as a
*trap*; a correction earned once becomes a permanent guard against regression.

PMbench supplies the study, the answer key, and the traps, and scores whatever
the workflow submits. What is under test is the workflow's task library — and,
when swapped, the model and harness behind it.

A trap is a real-world pathology plus a recipe for faking it in synthetic data
plus the correct handling. Contributing a trap requires no patient data.

`plan.md` is the source of truth for the build.

## v0 scenario

One scenario, `mab-poppk-v0`: a generic IgG1 mAb, two-compartment, linear
clearance, single IV infusion. Five scored items across four scorers and four
pharmacometric areas. Four traps live in the data; two are scored
explicitly, two implicitly.

| Trap | Scored | What it catches |
|------|--------|-----------------|
| **Weight** is the real covariate, via a power model (true exponent 0.75 on CL, 1.0 on Vc) | explicit (`cov_effects` — the effect size on each parameter, not just that WT matters) | assuming fixed allometric scaling instead of estimating the exponent; missing that WT also acts on volume |
| **Albumin** correlates with weight (r≈0.4) but has zero PK effect | explicit (decoy in `cov_effects`) | univariate covariate screening that never conditions on weight |
| **Creatinine clearance** is independent with zero effect | explicit (decoy in `cov_effects`) | small-molecule habits — mAbs are catabolized, not renally cleared |
| **BLQ** below LLOQ (~10%): predose zeros + genuine terminal censoring at the late samples (days 90/120/150) | implicit (surfaces in `error_model` / `disposition_params` numeric tolerance) | mishandling BLQ, which biases the terminal phase and inflates residual error |
| **Data-entry outliers** at subjects 5/50/95, day 7, DV×10 | explicit (`outlier_records`) | not screening for decimal-slip data-entry errors |

## Visible vs. held out

The agent runs Claude Code under the hood and explores its working directory, so
blinding is **physical**: held-out files are never copied into that directory.

- **`scenario/`** is agent-visible (protocol, SAP, data, submission template).
- **`evals/`** and **`build/`** are held out (answer key, traps, scorer, data
  generation, maintainer EDA plots).

## Layout

```
plan.md                              # source of truth
README.md
score.R                              # scenario-agnostic scorer (--truth flag)
scenarios/
  mab-poppk-v0/
    scenario/                        # AGENT-VISIBLE (flat packet, copied wholesale)
      protocol.md                    # study background, MOA, design, sampling
      sap.md                         # pop-PK analysis plan; dataset spec in Appendix A
      pmb-mab-poppk-v0.csv           # generated, committed for reproducibility
      submission.template.yaml       # the shape to fill
    evals/                           # HELD OUT
      truth.yaml                     # the answer key
      submission.example.yaml        # filled, imperfect — exercises the scorer
      traps/                         # one markdown file per trap
    build/                           # HELD OUT (build-time)
      generate.R                     # synthetic data, fixed seed (mrgsolve)
      plots.R                        # maintainer EDA plots -> build/figures/
```

## Requirements

R (tested on 4.3.3) with:

```r
install.packages(c("mrgsolve", "yaml"))   # data generation + scoring
install.packages("nlmixr2")               # fitting engine for workflow use; not needed to score
```

`mrgsolve` compiles the ODE model, so a C toolchain (gcc) must be present.

## Bootstrap (dataset + plots)

The dataset CSV is committed for reproducibility. To regenerate it from the fixed seed:

```sh
Rscript scenarios/mab-poppk-v0/build/generate.R
```

Prints sanity checks: terminal half-life ≈ 3 weeks, BLQ ≈ 10%, r(WT,ALB) ≈ 0.4,
and the three corrupted ROWIDs (`62`, `692`, `1322`).

Generate maintainer EDA plots (held out — never copied to the agent):

```sh
Rscript scenarios/mab-poppk-v0/build/plots.R
```

Reads the CSV above and writes two PNGs to `scenarios/mab-poppk-v0/build/figures/`:
- `spaghetti-by-dose.png` — concentration-time profiles by dose (log scale), injected day-7 outliers flagged in red
- `covariates.png` — WT distribution, WT vs ALB (r≈0.4), WT vs CRCL (r≈0)

## Use

Score a submission:

```sh
Rscript score.R --truth scenarios/mab-poppk-v0/evals/truth.yaml \
  scenarios/mab-poppk-v0/evals/submission.example.yaml
```

Prints a scorecard and writes `scorecard.yaml` next to the submission. The
example is deliberately imperfect (overall ≈ 0.71) — enough to see the traps
biting.

## Quickstart: the full benchmark loop

Scoring the example submission above exercises only the scorer. To benchmark a
real workflow, run all three stages: **proctor → run → score**. The example
assumes Modus is checked out as a sibling (`../modus`); swap in any workflow that
reads a `data/` packet and writes `submission.yaml`.

```sh
# 1. PROCTOR — stage the visible packet into a fresh project dir, outside this repo.
#    This copy is the blinding: only scenario/* travels; evals/ and build/ stay put.
./proctor.sh mab-poppk-v0 /tmp/pmbench-run

# 2. RUN — point the workflow under test at that project dir. RUN_LABEL names the
#    archived workspace so step 3 knows where the submission lands.
RUN_LABEL=mab-poppk-v0 ../modus/run.sh /tmp/pmbench-run

# 3. SCORE — grade the submission against the held-out answer key, from outside the loop.
Rscript score.R --truth scenarios/mab-poppk-v0/evals/truth.yaml \
  /tmp/pmbench-run/mab-poppk-v0_workspace/submission/submission.yaml
```

`proctor.sh <scenario-id> <project-dir>` copies `scenarios/<id>/scenario/*` into
`<project-dir>/data/` and refuses a project dir inside this repo (which would
break blinding by placing the workspace next to `evals/`).

### Baseline comparator

To put a number under the workflow, `baseline.sh` is the simplest thing that
satisfies the same contract: one headless agent call handed the proctored
`data/` packet and asked for a `submission.yaml`, with no task library, no
scaffolding, no codified expertise. It drops into step 2 in place of
`../modus/run.sh`, so the score difference isolates what the task library adds.

```sh
./proctor.sh mab-poppk-v0 /tmp/pmbench-baseline
./baseline.sh /tmp/pmbench-baseline
Rscript score.R --truth scenarios/mab-poppk-v0/evals/truth.yaml \
  /tmp/pmbench-baseline/baseline_workspace/submission/submission.yaml
```

It honors `AGENT_CMD` and `RUN_LABEL` exactly as `run.sh` does, so the
comparison holds the harness fixed and varies only the workflow.

#### A note on `--bare` and authentication

Both scripts default to OAuth login (the default for interactive Claude Code
installs). If you have API-key auth (`ANTHROPIC_API_KEY`, Bedrock, or Vertex),
prefer passing `--bare` via `AGENT_CMD`:

```sh
export AGENT_CMD="claude -p --bare --verbose --output-format stream-json --dangerously-skip-permissions"
RUN_LABEL=mab-poppk-v0 ../modus/run.sh /tmp/pmbench-run
./baseline.sh /tmp/pmbench-baseline
```

`--bare` prevents the host's CLAUDE.md and memory from leaking into the agent, which matters for reproducible comparisons.

The path in step 3 reflects how Modus archives a finished run: the live
`workspace/` is renamed to `<RUN_LABEL>_workspace/` on completion, so the
submission lands at `<project-dir>/<RUN_LABEL>_workspace/submission/submission.yaml`.
A different workflow will place its submission elsewhere — point `score.R` at
wherever it actually wrote.

## Scoring

Per item, in [0, 1]:

- **numeric**: `relErr = |submitted − expected| / |expected|`; `score = max(0, 1 − relErr / tol)`
- **categorical**: 1 if equal, else 0
- **set**: F1 of submitted vs expected. Both empty → 1; empty submission vs
  nonempty expected → 0. Decoys are absent from `expected`, so including one
  (like ALB) lowers precision on its own.
- **map**: a name→value map scored as `numeric` (per the item's tol) over the
  union of names, after resolving aliases. A matched name scores its numeric
  error; a missing or extra/decoy name scores 0. Both empty → 1. (Same
  precision/recall shape as `set`, valued by numeric error.)
- **map_nested**: a two-level map (e.g. parameter → covariate → value) flattened
  to `param::cov` keys, then scored like `map`. An effect on the wrong parameter
  or a decoy covariate is an unmatched key → 0.
- **unanswered** (key absent or null): 0, any scorer.

Aggregated as a weighted mean within each `pmx_area` (the pharmacometric
knowledge area) and overall. The area shape is the point: a demo-quality
workflow nails the easy numeric items and fails the traps.

## Contributing a trap

Copy `evals/traps/_template.md`, fill the four fields (failure mode, injection,
correct handling, how it surfaces in the protocol/SAP), and a maintainer wires it
into `build/generate.R`, `evals/truth.yaml`, and the SAP by hand. No machine-readable schema — wiring stays manual for now.
