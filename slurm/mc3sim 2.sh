#!/bin/bash
#SLURM for inference

#SBATCH -n 16
#SBATCH --mem=4G
#SBATCH --time=23:45:00
#SBATCH --gres=tmp:16G
#SBATCH --job-name=%GRID_TAG%_%SIMREP%_%SCRIPTID%
#SBATCH --output=/nobackup/%u/morphosim/logs/%GRID_TAG%_%SIMREP%_%SCRIPTID%.out
#SBATCH --error=/nobackup/%u/morphosim/logs/%GRID_TAG%_%SIMREP%_%SCRIPTID%.err
#SBATCH -p shared
#SBATCH --export=ALL

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.sh"

# --- Paths
RB=~/diss/revbayes/projects/cmake/build-mpi/rb-mpi
MORPHOSIM="$MORPHOSIM_DIR"
MATRIX="$MATRIX_DIR"

# Simulation directory: scenario / grid tag / replicate
SIM_SUBDIR=simulations/%SIMSCENARIO%/%GRID_TAG%/%SIMREP%

module load gcc/11.2
module load boost/1.78.0
module load openmpi/4.1.1

cd $MORPHOSIM
git pull origin main --rebase

cd $MATRIX
git pull origin main --rebase

echo "Starting inference: %SCRIPTID% on %SIMSCENARIO%/%GRID_TAG%/%SIMREP% at $(date)"
cd $MORPHOSIM

mpirun $RB \
  $MORPHOSIM/rbScripts/Inference/sim-mc3.Rev \
  $MATRIX/$SIM_SUBDIR \
  %SCRIPTID% \
  333 \
  %SEED%

echo "Inference complete at $(date)"

#--- Compress tree files
cd $MATRIX/$SIM_SUBDIR
for file in %SCRIPTID%_run_*.trees; do
  [ -f "$file" ] && \
    tar -czf "${file%.trees}.tar.gz" "$file" && \
    rm "$file"
done

#Record temp disk usage
du -hs $TMPDIR > mc3-tmpdir_usage_%SCRIPTID%.log 2>/dev/null || true

# --- Push outputs to the-matrix
cd $MATRIX
git add $SIM_SUBDIR/
git commit -m "Inference: %SIMSCENARIO%/%GRID_TAG%/%SIMREP%/%SCRIPTID%" || true
git pull origin main --rebase
git push origin main

echo "All done at $(date)"
