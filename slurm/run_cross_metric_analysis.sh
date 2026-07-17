#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --mem=8G
#SBATCH --time=00:45:00
#SBATCH -p shared
#SBATCH --job-name=cross_metric
#SBATCH --output=/nobackup/djfb16/morphosim/logs/cross_metric_%j.out
#SBATCH --error=/nobackup/djfb16/morphosim/logs/cross_metric_%j.err

#Merges tree accuracy with convergence/known-answer/CGR and tests whether
#models with better trees also have better results, at model and
#grid-cell level.

BRANCH="restore-75bb2e8"

module load r

cd /nobackup/djfb16/morphosim
echo "=== $(date '+%Y-%m-%d %H:%M:%S') starting cross_metric_analysis ==="
Rscript run/cross_metric_analysis.R
echo "=== $(date '+%Y-%m-%d %H:%M:%S') finished cross_metric_analysis ==="

cd /nobackup/djfb16/the-matrix
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
    git commit -m "cross_metric_analysis: results $(date '+%Y-%m-%d %H:%M')" 2>/dev/null || true
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
