#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --mem=2G
#SBATCH --time=00:45:00
#SBATCH -p shared
#SBATCH --job-name=cross_metric
#SBATCH --output=logs/cross_metric_%j.out
#SBATCH --error=logs/cross_metric_%j.err

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


module load r

cd "$MORPHOSIM_DIR"
echo "=== $(date '+%Y-%m-%d %H:%M:%S') starting cross_metric_analysis ==="
Rscript run/cross_metric/cross_metric_analysis.R
echo "=== $(date '+%Y-%m-%d %H:%M:%S') finished cross_metric_analysis ==="

cd "$MATRIX_DIR"
git checkout "$BRANCH"
git add results/cross_metric_gridcell.rds \
        results/cross_metric_gridcell.csv \
        results/cross_metric_model_scorecard.rds \
        results/cross_metric_model_scorecard.csv \
        results/cross_metric_rank_correlations.rds \
        results/cross_metric_rank_correlations.csv \
        results/cross_metric_gridcell_correlations.rds \
        results/cross_metric_gridcell_correlations.csv

if ! git diff --cached --quiet; then
  MAX_RETRIES=5
  ATTEMPT=0
  PUSHED=false
  while [ $ATTEMPT -lt $MAX_RETRIES ]; do
    ATTEMPT=$((ATTEMPT + 1))
    git pull --rebase origin "$BRANCH"
    git add results/cross_metric_gridcell.rds \
            results/cross_metric_gridcell.csv \
            results/cross_metric_model_scorecard.rds \
            results/cross_metric_model_scorecard.csv \
            results/cross_metric_rank_correlations.rds \
            results/cross_metric_rank_correlations.csv \
            results/cross_metric_gridcell_correlations.rds \
            results/cross_metric_gridcell_correlations.csv
    git commit -m "cross_metric_analysis: results $(date '+%Y-%m-%d')" 2>/dev/null || true
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
