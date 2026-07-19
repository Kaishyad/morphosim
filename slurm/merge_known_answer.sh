#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --mem=4G
#SBATCH --time=00:30:00
#SBATCH -p shared
#SBATCH --job-name=merge_known_answer
#SBATCH --output=/nobackup/djfb16/morphosim/logs/merge_known_answer_%j.out
#SBATCH --error=/nobackup/djfb16/morphosim/logs/merge_known_answer_%j.err

# Usage: sbatch --dependency=afterany:<job1>:...<jobN> slurm/merge_known_answer.sh [scenario]
# Merges per-model known_answer_summary files and pushes to GitHub.

SCENARIO="${1:-}"
BRANCH="clean-rebuild"

module load r

cd /nobackup/djfb16/morphosim
if [ -n "$SCENARIO" ]; then
  Rscript run/merge_known_answer.R --scenario "$SCENARIO"
else
  Rscript run/merge_known_answer.R
fi

cd /nobackup/djfb16/the-matrix
git checkout "$BRANCH"
git add results/known_answer_summary.rds results/known_answer_summary.csv

if ! git diff --cached --quiet; then
  git commit -m "merge: known answer summary${SCENARIO:+ ($SCENARIO)} $(date '+%Y-%m-%d %H:%M')"
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
    echo "WARNING: push failed after $MAX_RETRIES attempts."
    echo "Push manually: cd /nobackup/djfb16/the-matrix && git push origin $BRANCH"
  fi
else
  echo "No changes to commit."
fi
