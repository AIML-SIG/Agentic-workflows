#!/usr/bin/env bash
# PMbench baseline comparator: the simplest workflow that satisfies the contract.
#
# Where modus/run.sh drives fresh agent instances through a task library until
# every task verifiably passes, this is the floor it should beat: a SINGLE
# headless agent call, handed the proctored data/ packet with no scaffolding,
# no task library, no codified pharmacometric expertise -- just "here are the
# files, do the analysis, fill the submission." It exists to put a number under
# the workflow: how much of the score comes from the agent alone, and how much
# the task library actually adds.
#
# Same contract as any workflow PMbench scores: read a data/ packet, write
# workspace/submission/submission.yaml. So it slots straight into the loop in
# place of step 2 (proctor -> run -> score) from pharmbench/README.md.
#
# Usage: ./baseline.sh <project-dir>      # project-dir is a proctored dir (has data/)
#   e.g. ./proctor.sh mab-poppk-v0 /tmp/pmbench-baseline
#        ./baseline.sh /tmp/pmbench-baseline
set -euo pipefail

PROJECT_DIR="${1:-}"

if [ -z "$PROJECT_DIR" ]; then
    echo "ERROR: Project directory required"
    echo "Usage: $0 <project-dir>   (a proctored dir containing data/)"
    exit 1
fi
if [ ! -d "$PROJECT_DIR/data" ]; then
    echo "ERROR: $PROJECT_DIR has no data/ subdirectory. Proctor a scenario first:"
    echo "  ./proctor.sh <scenario-id> $PROJECT_DIR"
    exit 1
fi

ABS_PROJECT="$(cd "$PROJECT_DIR" && pwd)"

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

# Barebones prompt: the contract and nothing more -- no pharmacometric guidance,
# no task decomposition, no examples. Same read-only inputs and same one
# deliverable every scored workflow gets.
PROMPT="You are a pharmacometrician. Read the packet in ${ABS_PROJECT}/data/
(read-only: protocol, SAP, dataset, and submission.template.yaml). It defines the
analysis to perform and the reporting keys; nothing here in this prompt does.

Carry out that analysis with any tools you like (R, Python, ...), working under
${WORKSPACE}/. Then write the filled submission to EXACTLY ${SUBMISSION}, in the
template's shape and as the SAP defines each key. Report only what your analysis
supports -- leave an item null rather than guessing -- and set provenance.tool to
'baseline'. Do not traverse above ${ABS_PROJECT}."

log "PMbench baseline comparator (single agent call, no task library)"
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
    echo "Next -- score it against the held-out answer key (replace <scenario-id>):"
    echo "  Rscript score.R --truth scenarios/<scenario-id>/evals/truth.yaml \\"
    echo "    ${SUBMISSION}"
else
    log "WARNING: agent finished but no submission at ${SUBMISSION}."
    log "Inspect the run log: ${LOG_FILE}"
    exit 1
fi
