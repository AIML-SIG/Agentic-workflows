#!/usr/bin/env bash
# PMxbench proctor: stage a scenario's payload into a fresh project dir, so an
# agent run against it never sees an answer key.
#
# The copy IS the blinding, physical rather than promised. A scenario_XX/ folder
# is payload only (data.csv, sap.md, submission.template.yaml), but its sibling
# template_scenario_00/ carries truth.yaml, so the project dir must sit outside
# the pmxbench tree or the agent could walk up into it.
#
# Usage: ./proctor.sh <scenario> <project-dir>
#   e.g. ./proctor.sh scenario_00 /tmp/pmxbench-run
set -euo pipefail

SCENARIO_ID="${1:-}"
PROJECT_DIR="${2:-}"

if [ -z "$SCENARIO_ID" ] || [ -z "$PROJECT_DIR" ]; then
    echo "Usage: $0 <scenario> <project-dir>"
    echo "  e.g. $0 scenario_00 /tmp/pmxbench-run"
    exit 1
fi

PMX_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCENARIO_DIR="${PMX_DIR}/${SCENARIO_ID}"

if [ ! -f "${SCENARIO_DIR}/sap.md" ] || [ -e "${SCENARIO_DIR}/truth.yaml" ]; then
    echo "ERROR: ${SCENARIO_DIR} is not a payload-only scenario folder."
    echo "Available scenarios:"
    ls -1d "${PMX_DIR}"/scenario_* 2>/dev/null | xargs -n1 basename | sed 's/^/  /'
    exit 1
fi

mkdir -p "$PROJECT_DIR"
ABS_PROJECT="$(cd "$PROJECT_DIR" && pwd)"
case "${ABS_PROJECT}/" in
    "${PMX_DIR}/"*)
        echo "ERROR: project dir ${ABS_PROJECT} is inside the pmxbench tree,"
        echo "next to an answer key. Pick a dir outside ${PMX_DIR}."
        exit 1
        ;;
esac

DATA_DIR="${ABS_PROJECT}/data"
if [ -d "$DATA_DIR" ] && [ -n "$(ls -A "$DATA_DIR" 2>/dev/null)" ]; then
    echo "ERROR: ${DATA_DIR} already exists and is not empty. Use a fresh project dir."
    exit 1
fi

mkdir -p "$DATA_DIR"
cp "$SCENARIO_DIR"/* "$DATA_DIR"/

echo "Proctored '${SCENARIO_ID}' -> ${DATA_DIR}"
ls -1 "$DATA_DIR" | sed 's/^/  /'
echo
echo "Next: run your workflow against ${ABS_PROJECT}, then score its submission.yaml:"
echo "  Rscript score.R --truth <path/to/truth.yaml> <path/to/submission.yaml>"
