#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --mem=2G
#SBATCH --time=02:00:00
#SBATCH -p shared
#SBATCH --job-name=model_comparison
#SBATCH --output=logs/model_comparison_%j.out
#SBATCH --error=logs/model_comparison_%j.err

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
module load r

cd "$MORPHOSIM_DIR"
echo "=== $(date '+%Y-%m-%d %H:%M:%S') starting model_comparison ==="
Rscript run/model_comparison/model_comparison.R
echo "=== $(date '+%Y-%m-%d %H:%M:%S') finished model_comparison ==="

cd "$MATRIX_DIR"
git checkout "$BRANCH"
git add results/model_comparison_ranking.csv \
        results/model_comparison_friedman.csv \
        results/model_comparison_pairwise_mk.csv \
        results/model_comparison_pairwise_nt.csv \
        results/model_comparison_scenario_contrast.csv

if ! git diff --cached --quiet; then
  git commit -m "model_comparison: mk/nt tables $(date '+%Y-%m-%d')"
  git pull --rebase origin "$BRANCH"
  if git push origin "$BRANCH"; then
    echo "Pushed model comparison results."
  else
    echo "WARNING: push failed. Push manually with:"
    echo "  cd "$MATRIX_DIR" && git push origin $BRANCH"
  fi
else
  echo "No changes to commit."
fi
