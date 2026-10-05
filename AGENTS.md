# Notes for agents

- `tools/modus/`: a workflow that drives agents through a task library. See its README.
- `tools/pmxbench/`: the benchmark. `scenario_00/` is the payload a run gets;
  `template_scenario_00/` adds the answer key and `score.py`.
- Environment: the devcontainer (`.devcontainer/`). Official runs use
  `tools/modus/run_container.sh`.
- Smoke test: `cd tools/pmxbench/template_scenario_00 && python3 score.py submission.example.yaml`
  (overall 0.725).

## Two rules

- **Keep the answer key away from the agent.** Only `scenario_XX/*` goes into a
  run's `data/`, and the run dir lives outside this repo. `baseline.sh` refuses otherwise.
- **No scenario answers in the workflow.** Nothing specific to a scenario (which
  covariate is a decoy, which records are bad) goes into
  `tools/modus/ai_docs/task_library.json` or anything else the agent loads.
