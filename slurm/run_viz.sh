#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --mem=8G
#SBATCH --time=00:30:00
#SBATCH -p shared
#SBATCH --job-name=viz
#SBATCH --output=/nobackup/djfb16/morphosim/logs/viz_%j.out
#SBATCH --error=/nobackup/djfb16/morphosim/logs/viz_%j.err

# Usage: sbatch slurm/run_viz.sh
# Runs the full viz/ suite (all figures) and pushes results to the-matrix.
# Skip a single script by commenting it out in viz/run_all.R (imputation is
# already commented out there for now).

module load r

MORPHOSIM=/nobackup/djfb16/morphosim
MATRIX=/nobackup/djfb16/the-matrix

cd $MORPHOSIM

cd $MATRIX


# --- Run the viz suite ---
cd $MORPHOSIM
echo "=== $(date '+%Y-%m-%d %H:%M:%S') starting viz suite ==="
Rscript viz/run_all.R
echo "=== $(date '+%Y-%m-%d %H:%M:%S') finished viz suite ==="

# --- Push figures to the-matrix (retry-with-backoff, same pattern as
#     merge_tree_accuracy.sh / run_gam_threshold.sh) ---
cd $MATRIX
git add figures/

if ! git diff --cached --quiet; then
  MAX_RETRIES=5
  ATTEMPT=0
  PUSHED=false
  while [ $ATTEMPT -lt $MAX_RETRIES ]; do
    ATTEMPT=$((ATTEMPT + 1))
    git stash --include-untracked 2>/dev/null || true
    git pull --rebase origin main
    git stash pop 2>/dev/null || true
    git add figures/
    git commit -m "Update viz figures ($(date '+%Y-%m-%d %H:%M'))" || true
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
    echo "  cd $MATRIX && git push origin main"
  fi
else
  echo "No changes to commit."
fi

echo "All done at $(date)"
