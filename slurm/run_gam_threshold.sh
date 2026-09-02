#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --mem=2G
#SBATCH --time=4:00:00
#SBATCH -p shared
#SBATCH --job-name=gam_threshold
#SBATCH --output=logs/gam_threshold_%j.out
#SBATCH --error=logs/gam_threshold_%j.err

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
# usage: sbatch slurm/run_gam_threshold.sh [scenario]
# run after merge_tree_accuracy.sh has completed successfully

SCENARIO="${1:-mk}"

module load r

cd "$MORPHOSIM_DIR"
echo "=== $(date '+%Y-%m-%d %H:%M:%S') starting gam_threshold ${SCENARIO} ==="
Rscript run/gam_threshold/gam_threshold.R --scenario $SCENARIO
echo "=== $(date '+%Y-%m-%d %H:%M:%S') finished gam_threshold ${SCENARIO} ==="

cd "$MATRIX_DIR"
git checkout "$BRANCH"
git add results/threshold_summary_${SCENARIO}.rds \
        results/threshold_summary_${SCENARIO}.csv \
        results/gam_objects_${SCENARIO}.rds

if ! git diff --cached --quiet; then
  git commit -m "gam_threshold: ${SCENARIO} $(date '+%Y-%m-%d')"
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
    echo "  cd "$MATRIX_DIR" && git push origin $BRANCH"
  fi
else
  echo "No changes to commit."
fi
