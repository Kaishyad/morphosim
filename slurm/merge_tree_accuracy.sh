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
BRANCH="clean-rebuild"
module load r
cd /nobackup/djfb16/morphosim
if [ -n "$SCENARIO" ]; then
  Rscript run/merge_tree_accuracy.R --scenario "$SCENARIO"
else
  Rscript run/merge_tree_accuracy.R
fi
cd /nobackup/djfb16/the-matrix
git checkout "$BRANCH"
git add results/tree_accuracy_summary.rds results/tree_accuracy_per_rep.rds
if ! git diff --cached --quiet; then
  git commit -m "merge: tree accuracy summary${SCENARIO:+ ($SCENARIO)} $(date '+%Y-%m-%d %H:%M')"
  MAX_RETRIES=5
  ATTEMPT=0
  PUSHED=false
  while [ $ATTEMPT -lt $MAX_RETRIES ]; do
    ATTEMPT=$((ATTEMPT + 1))
    git pull --rebase origin "$BRANCH"
    if git push origin "$BRANCH"; then
      PUSHED=true
      break
    fi
    WAIT=$((RANDOM % 30 + 10))
    echo "Push failed (attempt $ATTEMPT/$MAX_RETRIES), retrying in ${WAIT}s..."
    sleep $WAIT
  done
  if [ "$PUSHED" = false ]; then
    echo "WARNING: push failed. Push manually:"
    echo "  cd /nobackup/djfb16/the-matrix && git push origin $BRANCH"
  fi
else
  echo "No changes to commit."
fi