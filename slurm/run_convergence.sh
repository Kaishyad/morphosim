#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --mem=8G
#SBATCH --time=06:00:00
#SBATCH -p shared
#SBATCH --job-name=convergence
#SBATCH --output=/nobackup/djfb16/morphosim/logs/convergence_%j.out
#SBATCH --error=/nobackup/djfb16/morphosim/logs/convergence_%j.err

module load r

cd /nobackup/djfb16/morphosim

# Usage: sbatch run_convergence.sh [max_trees] [scenario] [model]
# Examples:
#   sbatch run_convergence.sh 300 nt model1
#   sbatch run_convergence.sh 300 mk model4

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
Rscript run/check_convergence.R --scenario $SCENARIO $MODEL_ARG $MAX_TREES_ARG
echo "=== $(date '+%Y-%m-%d %H:%M:%S') finished ${SCENARIO}/${MODEL:-all} ==="

cd /nobackup/djfb16/the-matrix
git add results/convergence_summary.rds results/requeue_list.txt

if ! git diff --cached --quiet; then
  git commit -m "Convergence check: ${SCENARIO} ${MODEL:-all models}"
  git push origin main
else
  echo "No changes to commit."
fi