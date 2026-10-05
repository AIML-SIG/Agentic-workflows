#!/usr/bin/env bash
# Baseline: the simplest way to run an agent from a script.
#
# Where run.sh drives fresh agent instances through a task library until every
# task verifiably passes, this is the floor it should beat: ONE headless agent
# call, handed the data/ folder with no scaffolding, no task library and no
# codified pharmacometric expertise. The score gap between the two is what the
# task library adds.
#
# Same contract as run.sh: a project dir with data/ in, a submission.yaml out.
# For a PMxbench scenario, copy its three files into data/ first:
#
#   mkdir -p /tmp/pmx-baseline/data
#   cp tools/pmxbench/scenario_00/* /tmp/pmx-baseline/data/
#   tools/modus/baseline.sh /tmp/pmx-baseline
#
# Keep the project dir outside this repo, so the agent can't wander into
# tools/pmxbench/template_scenario_00/truth.yaml (the script refuses otherwise).
set -euo pipefail

PROJECT_DIR="${1:-}"

if [ -z "$PROJECT_DIR" ]; then
    echo "ERROR: Project directory required"
    echo "Usage: $0 <project-dir>   (a dir containing data/)"
    exit 1
fi
if [ ! -d "$PROJECT_DIR/data" ]; then
    echo "ERROR: $PROJECT_DIR has no data/ subdirectory. Copy a scenario's files into it first:"
    echo "  mkdir -p $PROJECT_DIR/data && cp tools/pmxbench/scenario_00/* $PROJECT_DIR/data/"
    exit 1
fi

ABS_PROJECT="$(cd "$PROJECT_DIR" && pwd)"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
case "${ABS_PROJECT}/" in "${REPO_ROOT}/"*)
    echo "ERROR: ${ABS_PROJECT} is inside this repo, next to answer keys. Use a dir outside it."
    exit 1;;
esac

# The agent harness, as a command prefix; the prompt is appended as the final
# argv. Headless claude -p, with --dangerously-skip-permissions because no human
# is present to answer prompts.
#   Codex example: AGENT_CMD='codex exec'
#
# Add --bare to AGENT_CMD to prevent host CLAUDE.md/memory/hooks from leaking
# into the agent. Required if using API-key auth instead of OAuth.
AGENT_CMD="${AGENT_CMD:-claude -p --verbose --output-format stream-json --dangerously-skip-permissions}"

RUN_LABEL="${RUN_LABEL:-baseline}"
TASK_TIMEOUT="${TASK_TIMEOUT:-3300}"          # seconds for the single call (default 55 min)

WORKSPACE="${ABS_PROJECT}/${RUN_LABEL}_workspace"
SUBMISSION_DIR="${WORKSPACE}/submission"
SUBMISSION="${SUBMISSION_DIR}/submission.yaml"
LOG_FILE="${ABS_PROJECT}/baseline_$(date +%Y%m%d_%H%M%S).log"

mkdir -p "$SUBMISSION_DIR"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"; }

# run_meta.yaml: facts this script knows authoritatively (which harness, which
# repo revision) for score.py --record to pick up, rather than trusting
# the agent's own provenance block to self-report them correctly.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_SHA="$(git -C "$SCRIPT_DIR" rev-parse --short=12 HEAD 2>/dev/null || echo unknown)"
HARNESS="$(awk '{print $1}' <<< "$AGENT_CMD")"
# Pull --model straight off AGENT_CMD when present -- more trustworthy than
# the agent's own provenance.model self-report (seen in practice reporting
# an estimation method, or left blank, instead of the LLM actually used).
MODEL_OVERRIDE="$(grep -oE -- '--model[= ]+[^ ]+' <<< "$AGENT_CMD" | sed -E 's/--model[= ]+//' || true)"
cat > "${WORKSPACE}/run_meta.yaml" <<EOF
harness: "${HARNESS}"
tool_sha: "${TOOL_SHA}"
model: "${MODEL_OVERRIDE}"
agent_cmd: "$(printf '%s' "$AGENT_CMD" | sed 's/"/\\"/g')"
EOF

# Barebones prompt: the contract and nothing more -- no pharmacometric guidance,
# no task decomposition, no examples. Same read-only inputs and same one
# deliverable every scored workflow gets.
PROMPT="You are a pharmacometrician. Read the packet in ${ABS_PROJECT}/data/
(read-only: sap.md, data.csv, and submission.template.yaml). It defines the
analysis to perform and the reporting keys; nothing here in this prompt does.

Carry out that analysis with any tools you like (R, Python, ...), working under
${WORKSPACE}/. Then write the filled submission to EXACTLY ${SUBMISSION}, in the
template's shape and as the SAP defines each key. Report only what your analysis
supports -- leave an item null rather than guessing -- and set provenance.tool to
'baseline'. Do not traverse above ${ABS_PROJECT}.

This is a single, non-interactive session: it ends the moment you stop taking
actions, and nothing resumes it afterward. If you background any long-running
work, keep actively waiting on it until it finishes before you stop."

log "Baseline (single agent call, no task library)"
log "Project directory: $ABS_PROJECT"
log "Agent command: $AGENT_CMD"
log "Submission target: $SUBMISSION"
log "Log file: $LOG_FILE"

# Single shot. No iteration loop, no escalation, no verification gate -- that is
# the point of the comparator. AGENT_CMD is word-split into argv; the prompt is a
# single final arg, never re-parsed by a shell.
timeout --foreground "$TASK_TIMEOUT" $AGENT_CMD "$PROMPT" >> "$LOG_FILE" 2>&1 || true

echo
if [ -f "$SUBMISSION" ]; then
    log "Done. Submission written: $SUBMISSION"
    echo
    echo "Next: submit it through the PMxbench issue form, or check it locally:"
    echo "  python3 tools/pmxbench/template_scenario_00/score.py ${SUBMISSION}"
else
    log "WARNING: agent finished but no submission at ${SUBMISSION}."
    log "Inspect the run log: ${LOG_FILE}"
    exit 1
fi
