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
  # Retry loop: pull --rebase before pushing to handle race conditions
  # when multiple per-model jobs finish around the same time and all
  # try to push simultaneously. Retries up to 5 times with a random
  # sleep (10-40s) between attempts to stagger concurrent jobs.
  MAX_RETRIES=5
  ATTEMPT=0
  PUSHED=false

  while [ $ATTEMPT -lt $MAX_RETRIES ]; do
    ATTEMPT=$((ATTEMPT + 1))

    git pull --rebase origin main
    if git push origin main; then
      PUSHED=true
      break
    fi

    WAIT=$((RANDOM % 30 + 10))
    echo "Push failed (attempt $ATTEMPT/$MAX_RETRIES), retrying in ${WAIT}s..."
    sleep $WAIT
  done

  if [ "$PUSHED" = false ]; then
    echo "WARNING: push failed after $MAX_RETRIES attempts."
    echo "convergence_summary.rds is saved locally — push manually with:"
    echo "  cd /nobackup/djfb16/the-matrix && git push origin main"
  fi
else
  echo "No changes to commit."
fi
