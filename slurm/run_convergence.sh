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

#sbatch run_convergence.sh [max_trees] [scenario] [model]


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

# --- Git push  disabled while .ckp cleanup is running on the-matrix ---
# Re-enable once the cleanup (screen: gitcleanup) has finished and pushed.
#
# cd /nobackup/djfb16/the-matrix
# git add results/convergence_summary.rds results/requeue_list.txt
#
# if ! git diff --cached --quiet; then
#   git commit -m "convergence: ${SCENARIO} ${MODEL:-all} $(date '+%Y-%m-%d %H:%M')"
#
#   MAX_RETRIES=5
#   ATTEMPT=0
#   PUSHED=false
#
#   while [ $ATTEMPT -lt $MAX_RETRIES ]; do
#     ATTEMPT=$((ATTEMPT + 1))
#
#     git pull --rebase origin main
#     if git push origin main; then