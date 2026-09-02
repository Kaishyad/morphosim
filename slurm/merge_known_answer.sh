#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --mem=2G
#SBATCH --time=00:30:00
#SBATCH -p shared
#SBATCH --job-name=merge_known_answer
#SBATCH --output=logs/merge_known_answer_%j.out
#SBATCH --error=logs/merge_known_answer_%j.err

# under sbatch, slurm copies this script into a job-specific spool directory
# before running it, so BASH_SOURCE no longer points at its real repo
# location and config.sh would fail to source. SLURM_SUBMIT_DIR is the
# directory sbatch was run from, which is what we want; fall back to
# BASH_SOURCE resolution when this script is run directly (not via sbatch).
if [ -n "$SLURM_SUBMIT_DIR" ]; then
  SCRIPT_DIR="$SLURM_SUBMIT_DIR/slurm"
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
source "$SCRIPT_DIR/config.sh"
# usage: sbatch --dependency=afterany:<job1>:...<jobN> slurm/merge_known_answer.sh [scenario]
# merges per-model known_answer_summary files and pushes to github

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
