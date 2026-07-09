#!/usr/bin/env bash
set -euo pipefail

echo "Installing R packages (mrgsolve, yaml, nlmixr2) via r2u/bspm binaries..."
Rscript -e 'install.packages(c("mrgsolve", "yaml", "nlmixr2"))'

echo "Verifying nlmixr2 loads..."
Rscript -e 'library(nlmixr2)'

echo "Installing Python deps (pharmbench/visualize_results.py)..."
pip install --user pyyaml

echo "Installing Claude Code CLI..."
npm install -g @anthropic-ai/claude-code
