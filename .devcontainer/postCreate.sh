#!/usr/bin/env bash
set -euo pipefail

echo "Installing R packages (mrgsolve, yaml, nlmixr2) via r2u/bspm binaries..."
Rscript -e 'install.packages(c("mrgsolve", "yaml", "nlmixr2"))'

echo "Verifying nlmixr2 loads..."
Rscript -e 'library(nlmixr2)'

echo "Installing Python deps (pmxbench score.py)..."
pip install --user pyyaml

# Agent harnesses are not baked in: install the one you use (npm install -g
# @anthropic-ai/claude-code, @openai/codex or @earendil-works/pi-coding-agent).
# Official runs (tools/modus/run_container.sh) install theirs at run time and
# record the version.
