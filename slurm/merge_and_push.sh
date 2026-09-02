#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --mem=2G
#SBATCH --time=01:00:00
#SBATCH -p shared
#SBATCH --job-name=merge_convergence
#SBATCH --output=logs/merge_%j.out
#SBATCH --error=logs/merge_%j.err

# under sbatch, slurm copies this script into a job-specific spool directory
# before running it, so BASH_SOURCE no longer points at its real repo
# location. SLURM_SUBMIT_DIR is the directory sbatch was run from, which is
# what we want; fall back to BASH_SOURCE resolution when this script is run
# directly (not via sbatch).
if [ -n "$SLURM_SUBMIT_DIR" ]; then
  SCRIPT_DIR="$SLURM_SUBMIT_DIR/slurm"
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

source "$SCRIPT_DIR/config.sh"
module load r

SCENARIO="${1:-}"

cd "$MORPHOSIM_DIR"
if [ -n "$SCENARIO" ]; then
  Rscript run/convergence/merge_convergence.R --scenario "$SCENARIO"
else
  Rscript run/convergence/merge_convergence.R
fi

cd "$MATRIX_DIR"
git checkout "$BRANCH"
git add results/convergence_summary.rds results/requeue_list.txt

if ! git diff --cached --quiet; then
  git commit -m "merge: convergence summary + requeue list $(date '+%Y-%m-%d')"
  git pull --rebase origin "$BRANCH"
  if git push origin "$BRANCH"; then
    echo "Pushed merged convergence results."
  else
    echo "WARNING: push failed. Push manually with:"
    echo "  cd "$MATRIX_DIR" && git push origin $BRANCH"
  fi
else
  echo "No changes to commit."
fi
