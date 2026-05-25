#!/bin/bash

# mc3sim.sh
# SLURM template for morphosim inference jobs.
# One job = one model × one simulation replicate.
# Filled in by MakeSlurm.R before submission; placeholders:
#   %SIMSCENARIO%  generative scenario ("nt" or "mk")
#   %SIMREP%       replicate ID, zero-padded to 3 digits (e.g. "sim001")
#   %SCRIPTID%     model script name without .Rev (e.g. "model1")
#   %SEED%         integer random seed
#   %GRID_TAG%     parameter combination tag (e.g. "tl1.0_n0.5_c50")
# Adapted from mc3sim.sh (supervisor / neotrans).

# --- Resource requests ---
#SBATCH -n 16
#SBATCH --mem=4G
#SBATCH --time=23:45:00
#SBATCH --gres=tmp:16G
#SBATCH --job-name=%GRID_TAG%_%SIMREP%_%SCRIPTID%
#SBATCH --output=/nobackup/%u/morphosim/logs/%GRID_TAG%_%SIMREP%_%SCRIPTID%.out
#SBATCH --error=/nobackup/%u/morphosim/logs/%GRID_TAG%_%SIMREP%_%SCRIPTID%.err
#SBATCH -p shared
#SBATCH --export=ALL

# --- Paths ---
RB=~/diss/revbayes/projects/cmake/build-mpi/rb-mpi
MORPHOSIM=/nobackup/$USER/morphosim
MATRIX=/nobackup/$USER/the-matrix

# Simulation directory: scenario / grid tag / replicate
SIM_SUBDIR=simulations/%SIMSCENARIO%/%GRID_TAG%/%SIMREP%

# --- Load modules ---
module load gcc/11.2
module load boost/1.78.0
module load openmpi/4.1.1

# --- Pull latest code ---
cd $MORPHOSIM
git pull origin main --rebase

# --- Pull latest data ---
cd $MATRIX
git pull origin main --rebase

# --- Run inference ---
echo "Starting inference: %SCRIPTID% on %SIMSCENARIO%/%GRID_TAG%/%SIMREP% at $(date)"
cd $MORPHOSIM

mpirun $RB \
  $MORPHOSIM/rbScripts/sim-mc3.Rev \
  $MATRIX/$SIM_SUBDIR \
  %SCRIPTID% \
  333 \
  %SEED%

echo "Inference complete at $(date)"

# --- Compress tree files ---
cd $MATRIX/$SIM_SUBDIR
for file in %SCRIPTID%_run_*.trees; do
  [ -f "$file" ] && \
    tar -czf "${file%.trees}.tar.gz" "$file" && \
    rm "$file"
done

# Record temp disk usage
du -hs $TMPDIR > mc3-tmpdir_usage_%SCRIPTID%.log 2>/dev/null || true

# --- Push outputs to the-matrix ---
cd $MATRIX
git add $SIM_SUBDIR/
git commit -m "Inference: %SIMSCENARIO%/%GRID_TAG%/%SIMREP%/%SCRIPTID%" || true
git pull origin main --rebase
git push origin main

echo "All done at $(date)"
