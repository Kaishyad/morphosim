#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --mem=16G
#SBATCH --time=6:00:00
#SBATCH -p shared
#SBATCH --job-name=tree_acc
#SBATCH --output=/nobackup/djfb16/morphosim/logs/tree_accuracy_%j.out
#SBATCH --error=/nobackup/djfb16/morphosim/logs/tree_accuracy_%j.err

# Usage: sbatch slurm/run_tree_accuracy.sh [scenario] [model]
# Examples:
#   sbatch slurm/run_tree_accuracy.sh mk model4
#   sbatch slurm/run_tree_accuracy.sh nt model8
# No git push here — run slurm/merge_tree_accuracy.sh after all model jobs finish.

SCENARIO="${1:-mk}"
MODEL="${2:-model1}"

module load r

cd /nobackup/djfb16/morphosim
echo "=== $(date '+%Y-%m-%d %H:%M:%S') starting tree_accuracy ${SCENARIO}/${MODEL} ==="
Rscript run/tree_accuracy.R --scenario $SCENARIO --model $MODEL
echo "=== $(date '+%Y-%m-%d %H:%M:%S') finished tree_accuracy ${SCENARIO}/${MODEL} ==="
