#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --mem=4G
#SBATCH --time=6:00:00
#SBATCH -p shared
#SBATCH --job-name=tree_acc
#SBATCH --output=logs/tree_accuracy_%j.out
#SBATCH --error=logs/tree_accuracy_%j.err

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
# sbatch slurm/run_tree_accuracy.sh [scenario] [model]

SCENARIO="${1:-mk}"
MODEL="${2:-model1}"

module load r

cd "$MORPHOSIM_DIR"
echo "=== $(date '+%Y-%m-%d %H:%M:%S') starting tree_accuracy ${SCENARIO}/${MODEL} ==="
Rscript run/tree_accuracy/tree_accuracy.R --scenario $SCENARIO --model $MODEL
echo "=== $(date '+%Y-%m-%d %H:%M:%S') finished tree_accuracy ${SCENARIO}/${MODEL} ==="
