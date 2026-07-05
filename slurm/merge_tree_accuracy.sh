#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --mem=8G
#SBATCH --time=01:00:00
#SBATCH -p shared
#SBATCH --job-name=merge_tree_acc
#SBATCH --output=/nobackup/djfb16/morphosim/logs/merge_tree_accuracy_%j.out
#SBATCH --error=/nobackup/djfb16/morphosim/logs/merge_tree_accuracy_%j.err

# Usage: sbatch --dependency=afterany:... slurm/merge_tree_accuracy.sh [scenario]

SCENARIO="${1:-}"

module load r

cd /nobackup/djfb16/morphosim
if [ -n "$SCENARIO" ]; then
  Rscript run/merge_tree_accuracy.R --scenario "$SCENARIO"
else
  Rscript run/merge_tree_accuracy.R
fi

cd /nobackup/djfb16/the-matrix
git add results/tree_accuracy_summary.rds results/tree_accuracy_per_rep.rds

if ! git diff --cached --quiet; then
  MAX_RETRIES=5
  ATTEMPT=0
  PUSHED=false
  while [ $ATTEMPT -lt $MAX_RETRIES ]; do
    ATTEMPT=$((ATTEMPT + 1))
    git stash --include-untracked 2>/dev/null || true
    git pull --rebase origin main
    git stash pop 2>/dev/null || true
    git add results/tree_accuracy_summary.rds results/tree_accuracy_per_rep.rds
    if git push origin main; then
      PUSHED=true
      break
    fi
    WAIT=$((RANDOM % 30 + 10))
    echo "Push failed (attempt $ATTEMPT/$MAX_RETRIES), retrying in ${WAIT}s..."
    sleep $WAIT
  done
  if [ "$PUSHED" = false ]; then
    echo "WARNING: push failed. Push manually:"
    echo "  cd /nobackup/djfb16/the-matrix && git push origin main"
  fi
else
  echo "No changes to commit."
fi
