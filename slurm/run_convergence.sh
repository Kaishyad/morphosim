#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --mem=4G
#SBATCH --time=06:00:00
#SBATCH -p shared
#SBATCH --job-name=convergence
#SBATCH --output=logs/convergence_%j.out
#SBATCH --error=logs/convergence_%j.err

# under sbatch, slurm copies this script into a job-specific spool directory
# before running it, so BASH_SOURCE no longer points at its real repo
# location and config.sh would fail to source. SLURM_SUBMIT_DIR is the
# directory sbatch was run from, which is what we want; fall back to
# BASH_SOURCE resolution when this script is run directly (not via sbatch).
if [ -n "$SLURM_SUBMIT_DIR" ]; then
  SCRIPT_DIR="$SLURM_SUBMIT_DIR/slurm"
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
source "$SCRIPT_DIR/config.sh"
module load r

cd "$MORPHOSIM_DIR"

# sbatch run_convergence.sh [max_trees] [scenario] [model]
# sbatch run_convergence.sh 300 mk model12

MAX_TREES_ARG=""
if [ -n "$1" ]; then
  MAX_TREES_ARG="--max-trees $1"
fi

SCENARIO="${2:-mk}"
MODEL="${3:-}"

MODEL_ARG=""
if [ -n "$MODEL" ]; then
  MODEL_ARG="--model $MODEL"
fi

echo "=== $(date '+%Y-%m-%d %H:%M:%S') starting ${SCENARIO}/${MODEL:-all} ==="
Rscript run/convergence/check_convergence.R --scenario $SCENARIO $MODEL_ARG $MAX_TREES_ARG
echo "=== $(date '+%Y-%m-%d %H:%M:%S') finished ${SCENARIO}/${MODEL:-all} ==="
