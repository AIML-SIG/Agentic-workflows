#!/usr/bin/env bash
# PMbench proctor: stage a scenario's *visible* packet into a fresh project dir,
# so the workflow under test runs against it without ever seeing the answer key.
#
# The copy IS the blinding -- physical, not a promise. Only scenario/* travels;
# evals/ (truth + traps) and build/ (data generation, EDA plots) are siblings of
# scenario/ and are never copied. Always run the workflow against the project dir
# this creates -- never in-place against the pharmbench tree, which would put a
# workspace/ next to evals/ and let the agent walk up into the answer key.
#
# Usage: ./proctor.sh <scenario-id> <project-dir>
#   e.g. ./proctor.sh mab-poppk-v0 /tmp/pmbench-run
set -euo pipefail

SCENARIO_ID="${1:-}"
PROJECT_DIR="${2:-}"

if [ -z "$SCENARIO_ID" ] || [ -z "$PROJECT_DIR" ]; then
    echo "Usage: $0 <scenario-id> <project-dir>"
    echo "  e.g. $0 mab-poppk-v0 /tmp/pmbench-run"
    exit 1
fi

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SCENARIO_DIR="${REPO_DIR}/scenarios/${SCENARIO_ID}/scenario"

if [ ! -d "$SCENARIO_DIR" ]; then
    echo "ERROR: no visible packet at ${SCENARIO_DIR}"
    echo "Available scenarios:"
    ls -1 "${REPO_DIR}/scenarios" 2>/dev/null | sed 's/^/  /'
    exit 1
fi

# Blinding guard: the project dir must live OUTSIDE the pharmbench tree. If it
# sat inside, the agent could traverse from workspace/ up into the held-out
# evals/. Refuse rather than silently break the blinding.
mkdir -p "$PROJECT_DIR"
ABS_PROJECT="$(cd "$PROJECT_DIR" && pwd)"
case "${ABS_PROJECT}/" in
    "${REPO_DIR}/"*)
        echo "ERROR: project dir ${ABS_PROJECT} is inside the pharmbench repo."
        echo "That would place workspace/ beside the held-out evals/. Pick a dir outside ${REPO_DIR}."
        exit 1
        ;;
esac

DATA_DIR="${ABS_PROJECT}/data"
if [ -d "$DATA_DIR" ] && [ -n "$(ls -A "$DATA_DIR" 2>/dev/null)" ]; then
    echo "ERROR: ${DATA_DIR} already exists and is not empty. Use a fresh project dir."
    exit 1
fi

mkdir -p "$DATA_DIR"
# The packet is flat, so a single glob lands every file directly in data/.
cp "$SCENARIO_DIR"/* "$DATA_DIR"/

echo "Proctored '${SCENARIO_ID}' -> ${DATA_DIR}"
echo "Copied (visible packet only):"
ls -1 "$DATA_DIR" | sed 's/^/  /'
echo
echo "Held out (NOT copied): evals/ (answer key + traps), build/ (data gen + EDA plots)"
echo
echo "Next:"
echo "  RUN_LABEL=${SCENARIO_ID} ../modus/run.sh ${ABS_PROJECT}"
echo "  Rscript score.R --truth scenarios/${SCENARIO_ID}/evals/truth.yaml \\"
echo "    ${ABS_PROJECT}/${SCENARIO_ID}_workspace/submission/submission.yaml"
