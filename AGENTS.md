# Notes for agents

- `tools/pmxbench/`: the benchmark. A run gets `scenario_00/`;
  `template_scenario_00/` adds the answer key and `score.py`.
- `tools/modus/`: the workflows. `run.sh` uses a task library; `baseline.sh` is
  one bare agent call, the floor `run.sh` should beat.
- Run a baseline: copy `tools/pmxbench/scenario_00/*` into `<dir>/data/`, outside
  this repo, then `tools/modus/run_container.sh <dir>`.
- Check the scorer: `cd tools/pmxbench/template_scenario_00 && python3 score.py submission.example.yaml`
  should print overall 0.725.

## Two rules

- **Keep the answer key away from the agent.** Only `scenario_XX/*` goes into a
  run, and runs live outside this repo.
- **No scenario answers in the workflow.** Nothing scenario-specific (decoy
  covariates, bad records) goes into anything the agent loads.
