#!/usr/bin/env bash
# The official PMxbench environment: baseline.sh (or run.sh) inside a fresh container.
#
# The image is built from .devcontainer/ (the same definition Codespaces uses),
# but each run gets its own throwaway container with ONLY the project dir
# mounted: no repo, no answer keys, no state left over from earlier runs.
#
# Before the agent's clock starts, the container installs the standard R
# packages (as binaries, seconds not minutes) and the harness from npm. Nothing
# is pinned; baseline.sh records every version into run_meta.yaml instead.
#
#   mkdir -p ~/pmx-runs/my-run/data
#   cp tools/pmxbench/scenario_00/* ~/pmx-runs/my-run/data/
#   OPENROUTER_API_KEY=... AGENT_CMD='pi -p --mode json --model openrouter/<id>' \
#     tools/modus/run_container.sh ~/pmx-runs/my-run
#
# HARNESS_VERSION pins the harness (e.g. 0.80.3); default latest. Either way
# the version used is recorded.
# RUNNER=run.sh runs the Modus workflow instead of the baseline. AGENT_CMD,
# RUN_LABEL, TASK_TIMEOUT, MAX_ITERATIONS and UNATTENDED pass through. Set
# REBUILD=1 to rebuild the image (e.g. after editing .devcontainer/).
set -euo pipefail

PROJECT_DIR="${1:-}"
if [ -z "$PROJECT_DIR" ] || [ ! -d "$PROJECT_DIR/data" ]; then
    echo "Usage: $0 <project-dir>   (a dir containing data/, outside this repo)"
    exit 1
fi
ABS_PROJECT="$(cd "$PROJECT_DIR" && pwd)"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
case "${ABS_PROJECT}/" in "${REPO_ROOT}/"*)
    echo "ERROR: ${ABS_PROJECT} is inside this repo, next to answer keys. Use a dir outside it."
    exit 1;;
esac

IMAGE="${PMX_IMAGE:-pmx-agent}"
RUNNER="${RUNNER:-baseline.sh}"     # or run.sh, for the Modus workflow
case "$RUNNER" in baseline.sh|run.sh) ;; *) echo "ERROR: RUNNER must be baseline.sh or run.sh"; exit 1;; esac
AGENT_CMD="${AGENT_CMD:-claude -p --verbose --output-format stream-json --dangerously-skip-permissions}"
HARNESS="$(awk '{print $1}' <<< "$AGENT_CMD")"
case "$HARNESS" in
    claude) HARNESS_PKG="@anthropic-ai/claude-code" ;;
    codex)  HARNESS_PKG="@openai/codex" ;;
    pi)     HARNESS_PKG="@earendil-works/pi-coding-agent" ;;
    *) echo "ERROR: no npm package known for harness '$HARNESS'. Add it to $0."; exit 1 ;;
esac

if [ -n "${REBUILD:-}" ] || ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    devcontainer build --workspace-folder "$REPO_ROOT" --image-name "$IMAGE"
fi

# Setup runs as root (apt-backed R binaries need it); the agent runs as the
# image's unprivileged user, since some harnesses refuse to skip permission
# prompts as root.
# rxode2 compiles every model at run time and links BLAS, LAPACK and gfortran,
# which the r2u binaries ship only as runtime libraries; the -dev packages
# provide the link names. The compile check fails the run here, before the
# agent's clock starts, instead of leaving the agent to discover it.
SETUP='set -e
{ apt-get update -q && apt-get install -y -q libblas-dev liblapack-dev gfortran; } >/tmp/setup.log 2>&1
Rscript -e "options(bspm.version.check = FALSE); install.packages(c(\"nlmixr2\", \"mrgsolve\", \"yaml\"))" >>/tmp/setup.log 2>&1
runuser -u vscode -- Rscript -e "rxode2::rxode2(\"d/dt(x) = -x\")" >>/tmp/setup.log 2>&1 ||
    { echo "Setup failed: rxode2 cannot compile a model. See /tmp/setup.log:"; tail -20 /tmp/setup.log; exit 1; }
npm install -g "$HARNESS_PKG@$HARNESS_VERSION" >>/tmp/setup.log 2>&1
exec runuser -u vscode -- env HOME=/home/vscode PATH="$PATH" \
    "/opt/pmx/tools/modus/$RUNNER" /work'

# tools/modus/ holds the workflows and no answer keys, so it is safe to mount.
docker run --rm \
    -v "${ABS_PROJECT}:/work" \
    -v "${REPO_ROOT}/tools/modus:/opt/pmx/tools/modus:ro" \
    -e AGENT_CMD="$AGENT_CMD" -e HARNESS_PKG="$HARNESS_PKG" -e RUNNER="$RUNNER" \
    -e HARNESS_VERSION="${HARNESS_VERSION:-latest}" \
    -e RUN_LABEL -e TASK_TIMEOUT -e MAX_ITERATIONS -e UNATTENDED \
    -e ANTHROPIC_API_KEY -e OPENROUTER_API_KEY -e OPENAI_API_KEY \
    -e PMX_CONTAINER="$(docker image inspect --format '{{.Id}}' "$IMAGE")" \
    -e PMX_TOOL_SHA="$(git -C "$REPO_ROOT" rev-parse --short=12 HEAD 2>/dev/null || echo unknown)" \
    "$IMAGE" bash -c "$SETUP"
