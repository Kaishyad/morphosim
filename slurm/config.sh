#!/bin/bash
# Shared configuration for every script in slurm/.
#
# Every slurm/*.sh script sources this file first, so there's one place to
# change the repo locations and git branch instead of editing them in ~20
# scripts. Defaults assume the standard Hamilton /nobackup/<user>/ layout;
# override any of them by exporting the variable before you run/submit a
# script, e.g.:
#
#   export MORPHOSIM_DIR=/nobackup/abcd12/dev-morphosim
#   sbatch slurm/run_convergence.sh

: "${MORPHOSIM_DIR:=/nobackup/${USER}/morphosim}"
: "${MATRIX_DIR:=/nobackup/${USER}/the-matrix}"
: "${BRANCH:=clean-rebuild}"
