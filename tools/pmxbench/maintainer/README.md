# PMxbench maintainer tooling

Everything a participant does not need: the scorer, the blinding proctor, the
baseline comparator, the leaderboard generator, and the recorded runs. It is
slated to move to the private repo that will hold the answer keys for scenario 01
onward. Until then it stays here because `.github/workflows/site.yml` builds the
public leaderboard from `results/`.

Commands below run from this folder.

## Requirements

R (tested on 4.3.3) with `install.packages(c("mrgsolve", "yaml"))`; `mrgsolve`
needs a C toolchain. Python 3 with `pyyaml` for the leaderboard.

## Score a submission

```sh
Rscript score.R --truth ../template_scenario_00/truth.yaml path/to/submission.yaml
```

Prints a scorecard and writes `scorecard.yaml` next to the submission. Smoke test:
`submission.example.yaml` is deliberately imperfect (overall ≈ 0.72, falls for the
ALB decoy, misses one outlier).

For an issue-form submission: save the pasted YAML to a file, then score it with
`--record` (below).

## Run an agent against a scenario: proctor → run → score

```sh
./proctor.sh scenario_00 /tmp/pmxbench-run      # copies the payload into /tmp/pmxbench-run/data/
# run the workflow under test against /tmp/pmxbench-run; it writes a submission.yaml
Rscript score.R --truth ../template_scenario_00/truth.yaml <path/to/submission.yaml>
```

The copy is the blinding. `proctor.sh` refuses a template folder (it holds an
answer key) and refuses a project dir inside `tools/pmxbench`, where an agent could
walk up into `template_scenario_00/truth.yaml`.

### Baseline comparator

`baseline.sh` is the simplest workflow that meets the contract: one headless agent
call handed the proctored `data/` folder and asked for a `submission.yaml`, with no
scaffolding. The score gap between it and a workflow is what the workflow adds.

```sh
./proctor.sh scenario_00 /tmp/pmxbench-baseline
./baseline.sh /tmp/pmxbench-baseline
Rscript score.R --truth ../template_scenario_00/truth.yaml \
  /tmp/pmxbench-baseline/baseline_workspace/submission/submission.yaml
```

It honors `AGENT_CMD` (e.g. `AGENT_CMD='codex exec'`), `RUN_LABEL` and
`TASK_TIMEOUT`. With API-key auth, add `--bare` to `AGENT_CMD` so the host's
CLAUDE.md and memory do not leak into the agent.

## Record a run for the leaderboard

```sh
Rscript score.R --record --truth ../template_scenario_00/truth.yaml <path/to/submission.yaml>
```

Writes `results/<slug>/{scorecard.yaml,submission.yaml}`. Commit only that new
folder. `--record` is opt-in so ad hoc scoring never creates a leaderboard entry.
Raw agent logs are never archived: `results/*/raw_log/` is gitignored because a
harness that echoes its environment writes API keys into the transcript.

**Do not commit `docs/leaderboard.qmd`.** CI generates it from `results/` on every
push to `main`. To preview it locally (this also re-renders each run's
`slide.html`):

```sh
python3 generate_leaderboard.py --exclude-dataset pmb-mab-pkpd-v0
```

`--exclude-dataset` keeps the retired `pmb-mab-pkpd-v0` runs off the board; CI
always passes it. The leaderboard finds each run's answer key by matching the
run's dataset against `meta.dataset` in `../*/truth.yaml`.

## Scoring

Per item, in [0, 1]:

- **numeric**: `relErr = |submitted − expected| / |expected|`; `score = exp(−relErr / tol)`.
  1 at zero error, ~0.37 at exactly 1× tol, decaying smoothly beyond. When
  `expected == 0`, `tol` is an absolute tolerance.
- **categorical**: 1 if equal, else 0.
- **set**: F1 of submitted vs expected. Both empty → 1.
- **map**: name → value, each matched name scored as numeric after resolving
  aliases; a missing or extra name scores 0.
- **map_nested**: parameter → covariate → value, flattened to `param::cov` keys,
  then scored like `map`. A decoy covariate is an unmatched key and scores 0.
- **unanswered** (key absent or null): 0.

Items are averaged by weight within each `pmx_area` and overall.

## Adding a scenario

Copy `../template_scenario_00/` to the private repo, change the true model and
traps in `generate.R`, run it, write `truth.yaml` from what it prints, and adjust
`sap.md` and the template. Publish only `data.csv`, `sap.md` and
`submission.template.yaml` as `../scenario_XX/`.
