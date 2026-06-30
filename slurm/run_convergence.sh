#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --mem=8G
#SBATCH --time=12:00:00
#SBATCH -p shared
#SBATCH --job-name=convergence
#SBATCH --output=/nobackup/djfb16/morphosim/logs/convergence.out
#SBATCH --error=/nobackup/djfb16/morphosim/logs/convergence.err

module load r

cd /nobackup/djfb16/morphosim

# Optional: pass a tree-distance cap as the first script argument, e.g.
#   sbatch run_convergence.sh 300
# Leave blank to use the default (1000, or whatever TREE_ESS_MAX_TREES is
# set to in _setup.R).
MAX_TREES_ARG=""
if [ -n "$1" ]; then
  MAX_TREES_ARG="--max-trees $1"
fi

for model in model1 model2 model3 model4 model5 model6 model7 model8 model9 model10 model11 model12; do
  echo "=== $(date '+%Y-%m-%d %H:%M:%S') starting $model ==="
  Rscript run/check_convergence.R --scenario mk --model $model $MAX_TREES_ARG
  echo "=== $(date '+%Y-%m-%d %H:%M:%S') finished $model ==="
done

cd /nobackup/djfb16/the-matrix
git add results/convergence_summary.rds results/requeue_list.txt

# Only commit/push if there's actually something to commit — otherwise
# `git commit` exits non-zero on "nothing to commit", which would mark
# this SLURM job as failed even though the convergence check itself
# succeeded (e.g. a re-run that found nothing new to check).
if ! git diff --cached --quiet; then
  git commit -m "Convergence check: mk all models"
  git push origin main
else
  echo "No changes to commit — convergence_summary.rds and requeue_list.txt unchanged."
fi