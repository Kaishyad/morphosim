#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --mem=8G
#SBATCH --time=12:00:00
#SBATCH -p shared
#SBATCH --job-name=convergence
#SBATCH --output=/nobackup/djfb16/morphosim/logs/convergence_%j.out
#SBATCH --error=/nobackup/djfb16/morphosim/logs/convergence_%j.err

module load r

cd /nobackup/djfb16/morphosim

# Usage: sbatch run_convergence.sh [max_trees] [scenario]
# Examples:
#   sbatch run_convergence.sh 300 nt
#   sbatch run_convergence.sh 300 mk
#   sbatch run_convergence.sh 300     # defaults to mk

MAX_TREES_ARG=""
if [ -n "$1" ]; then
  MAX_TREES_ARG="--max-trees $1"
fi

SCENARIO="${2:-mk}"

for model in model1 model2 model3 model4 model5 model6 model7 model8 model9 model10 model11 model12; do
  echo "=== $(date '+%Y-%m-%d %H:%M:%S') starting ${SCENARIO}/${model} ==="
  Rscript run/check_convergence.R --scenario $SCENARIO --model $model $MAX_TREES_ARG
  echo "=== $(date '+%Y-%m-%d %H:%M:%S') finished ${SCENARIO}/${model} ==="
done

cd /nobackup/djfb16/the-matrix
git add results/convergence_summary.rds results/requeue_list.txt

if ! git diff --cached --quiet; then
  git commit -m "Convergence check: $SCENARIO all models"
  git push origin main
else
  echo "No changes to commit."
fi