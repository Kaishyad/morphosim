#!/bin/bash
# shared configuration for every script in slurm/. sourced first by each
# script, so repo locations and the git branch only need changing here.
# defaults assume the standard hamilton /nobackup/<user>/ layout; override
# any of them by exporting the variable before running/submitting a script:
#
#   export MORPHOSIM_DIR=/nobackup/abcd12/dev-morphosim
#   sbatch slurm/run_convergence.sh

: "${MORPHOSIM_DIR:=/nobackup/${USER}/morphosim}"
: "${MATRIX_DIR:=/nobackup/${USER}/the-matrix}"
: "${BRANCH:=clean-rebuild}"
