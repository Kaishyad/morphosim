#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --mem=2G
#SBATCH --time=00:30:00
#SBATCH -p shared
#SBATCH --job-name=merge_known_answer
#SBATCH --output=logs/merge_known_answer_%j.out
#SBATCH --error=logs/merge_known_answer_%j.err

# Under sbatch, SLURM copies this script into a job-specific spool directory
# before executing it, so ${BASH_SOURCE[0]} no longer points at its real
# location in the repo -- config.sh would silently fail to source (MATRIX_DIR/
# MORPHOSIM_DIR/BRANCH stay unset) and any $MATRIX_DIR-based cd/git command
# later in this script would then operate on the wrong directory. SLURM sets
# SLURM_SUBMIT_DIR to the directory `sbatch` was run from, which is what we
# actually want. Fall back to BASH_SOURCE-based resolution for the case where
# this script is run directly (not via sbatch).
if [ -n "$SLURM_SUBMIT_DIR" ]; then
  SCRIPT_DIR="$SLURM_SUBMIT_DIR/slurm"
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
source "$SCRIPT_DIR/config.sh"
# Usage: sbatch --dependency=afterany:<job1>:...<jobN> slurm/merge_known_answer.sh [scenario]
# Merges per-model known_answer_summary files and pushes to GitHub.

SCENARIO="${1:-}"

module load r

cd "$MORPHOSIM_DIR"
if [ -n "$SCENARIO" ]; then
  Rscript run/known_answer/merge_known_answer.R --scenario "$SCENARIO"
else
  Rscript run/known_answer/merge_known_answer.R
fi

cd "$MATRIX_DIR"
git checkout "$BRANCH"
git add results/known_answer_summary.rds results/known_answer_summary.csv

if ! git diff --cached --quiet; then
  git commit -m "merge: known answer summary${SCENARIO:+ ($SCENARIO)} $(date '+%Y-%m-%d')"
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
    echo "Push manually: cd "$MATRIX_DIR" && git push origin $BRANCH"
  fi
else
  echo "No changes to commit."
fi
