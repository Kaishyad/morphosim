#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --mem=16G
#SBATCH --time=4:00:00
#SBATCH -p shared
#SBATCH --job-name=gam_threshold
#SBATCH --output=/nobackup/djfb16/morphosim/logs/gam_threshold_%j.out
#SBATCH --error=/nobackup/djfb16/morphosim/logs/gam_threshold_%j.err

# Usage: sbatch slurm/run_gam_threshold.sh [scenario]
# Run after merge_tree_accuracy.sh has completed successfully.

SCENARIO="${1:-mk}"
BRANCH="restore-75bb2e8"

module load r

cd /nobackup/djfb16/morphosim
echo "=== $(date '+%Y-%m-%d %H:%M:%S') starting gam_threshold ${SCENARIO} ==="
Rscript run/gam_threshold.R --scenario $SCENARIO
echo "=== $(date '+%Y-%m-%d %H:%M:%S') finished gam_threshold ${SCENARIO} ==="

cd /nobackup/djfb16/the-matrix
git checkout "$BRANCH"
git add results/threshold_summary_${SCENARIO}.rds \
        results/threshold_summary_${SCENARIO}.csv \
        results/gam_objects_${SCENARIO}.rds

if ! git diff --cached --quiet; then
  git commit -m "gam_threshold: ${SCENARIO} $(date '+%Y-%m-%d %H:%M')"
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
