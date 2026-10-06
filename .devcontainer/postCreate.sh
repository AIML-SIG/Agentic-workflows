#!/usr/bin/env bash
set -euo pipefail

# rxode2 compiles every model and links these; r2u ships only the runtime libs.
echo "Installing BLAS/LAPACK/gfortran link libraries for model compilation..."
sudo apt-get update -q && sudo apt-get install -y -q libblas-dev liblapack-dev gfortran

echo "Installing R packages (mrgsolve, yaml, nlmixr2) via r2u/bspm binaries..."
# version.check off: take an r2u binary even when CRAN has a newer source,
# rather than compiling (rxode2ll from source takes many minutes).
Rscript -e 'options(bspm.version.check = FALSE); install.packages(c("mrgsolve", "yaml", "nlmixr2"))'

# Loading nlmixr2 is not enough: it loads fine when models cannot compile.
echo "Verifying rxode2 can compile a model..."
Rscript -e 'rxode2::rxode2("d/dt(x) = -x")'

echo "Installing Python deps (pmxbench score.py)..."
pip install --user pyyaml

# Agent harnesses are not baked in: install the one you use (npm install -g
# @anthropic-ai/claude-code, @openai/codex or @earendil-works/pi-coding-agent).
# Official runs (tools/modus/run_container.sh) install theirs at run time and
# record the version.
