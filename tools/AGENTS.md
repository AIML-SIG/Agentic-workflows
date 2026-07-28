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

**Fast path: skip this section.** Open the repo in the provided devcontainer —
GitHub Codespaces (Code → Codespaces → Create codespace), VS Code's Dev
Containers extension, or locally via `devcontainer up --workspace-folder .`
(needs Docker + `npm install -g @devcontainers/cli`) — and `.devcontainer/`
installs R (`mrgsolve`, `yaml`, `nlmixr2` via prebuilt r2u binaries, not source
compiles), Python, Node, and the Claude Code CLI automatically. `ANTHROPIC_API_KEY`
and `OPENROUTER_API_KEY` are picked up from a Codespaces secret or a local
`.devcontainer/.env` (copy `.env.example`) — see that file for details.

Everything below is what the devcontainer is doing for you, useful if you're
bootstrapping without it or something needs debugging.

**Driving an already-running devcontainer via `docker exec` (not the VS Code
Dev Containers UI).** `docker exec` doesn't go through the Dev Containers
launch flow, so it skips the `remoteEnv` step that would otherwise inject
`ANTHROPIC_API_KEY`/`OPENROUTER_API_KEY` from the host. Two things to get
right:

- Exec in as `-u vscode`, not root — Claude Code's
  `--dangerously-skip-permissions` refuses to run as root/sudo, and root has no
  home-directory credentials anyway.
- Pass keys explicitly per invocation: `docker exec -e OPENROUTER_API_KEY=...
  -u vscode <container> ...` (read them from `.devcontainer/.env`). Until a
  real `ANTHROPIC_API_KEY` is filled into `.devcontainer/.env`, `claude` has no
  API-key auth path in the container; the workaround is OAuth — copy a
  freshly-authenticated host session's `~/.claude/.credentials.json` into the
  container (`docker cp` to `/home/vscode/.claude/.credentials.json`, then
  `chown vscode:vscode` + `chmod 600`). Once `.devcontainer/.env` has a real
  key, drop this step and use the key directly like `OPENROUTER_API_KEY` above.

Verify, and install what's missing, before running anything:

1. **Agent harness** — needed only to *run* the workflow. `claude` (Claude Code
   CLI) is the default. `pi` (https://pi.dev, `npm install -g
   @earendil-works/pi-coding-agent`) works via `AGENT_CMD='pi -p --mode json
   --provider openrouter --model <provider/model>'` with `OPENROUTER_API_KEY`
   set. `codex` (`npm install -g @openai/codex`) needs more than
   `AGENT_CMD='codex exec'` to reach a non-OpenAI provider like OpenRouter --
   its default config otherwise silently keeps hitting `api.openai.com` (401,
   no key there) even with a custom provider defined in `~/.codex/config.toml`:
   ```toml
   [model_providers.openrouter]
   name = "OpenRouter"
   base_url = "https://openrouter.ai/api/v1"
   env_key = "OPENROUTER_API_KEY"
   wire_api = "responses"   # "chat" is deprecated as of codex-cli 0.143
   ```
   then pass provider/model as explicit CLI overrides -- the config file's
   top-level `model_provider`/`model` keys were not picked up in testing:
   `AGENT_CMD='codex exec --json --skip-git-repo-check
   --dangerously-bypass-approvals-and-sandbox -c model_provider=openrouter -m
   <provider/model>'`. `--skip-git-repo-check` is required since a proctored
   project dir isn't a git repo; `--dangerously-bypass-approvals-and-sandbox`
   is required for the same reason `--dangerously-skip-permissions` is for
   claude -- codex's default sandbox is read-only, which silently blocks
   writing `submission.yaml`. Check whichever harness is on `PATH`.
2. **R** with `mrgsolve`, `yaml`, and `nlmixr2`. `mrgsolve` compiles an ODE
   model (data generation), so a C toolchain (gcc) must be present. `nlmixr2`
   is the fitting engine the workflow tasks use at run time. Install:
   `Rscript -e 'install.packages(c("mrgsolve","yaml","nlmixr2"))'`. Confirm
   with `Rscript -e 'library(nlmixr2)'`.
3. **Python 3 + pyyaml** — for `pharmbench/generate_leaderboard.py` (renders
   `docs/leaderboard.qmd` and the per-run drill-down slides; CI runs it on every push
   to `main`, so you only need it to preview the board locally) and for the optional
   `pharmbench/visualize_results.py`.

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
  general-competence altitude.

Beyond that, the per-folder READMEs are the source of truth.
