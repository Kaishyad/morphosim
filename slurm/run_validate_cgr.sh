#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --mem=6G
#SBATCH --time=04:00:00
#SBATCH -p shared
#SBATCH --job-name=validate_cgr
#SBATCH --output=logs/validate_cgr_%j.out
#SBATCH --error=logs/validate_cgr_%j.err


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
echo "=== $(date '+%Y-%m-%d %H:%M:%S') starting validate_cgr ==="
Rscript run/validate_cgr/validate_cgr.R
echo "=== $(date '+%Y-%m-%d %H:%M:%S') finished validate_cgr ==="

cd "$MATRIX_DIR"
git checkout "$BRANCH"
git add results/cgr_coverage.rds results/cgr_coverage.csv

if ! git diff --cached --quiet; then
  git commit -m "validate_cgr: coverage results $(date '+%Y-%m-%d')"
  git pull --rebase origin "$BRANCH"
  if git push origin "$BRANCH"; then
    echo "Pushed CGR coverage results."
  else
    echo "WARNING: push failed. Push manually with:"
    echo "  cd "$MATRIX_DIR" && git push origin $BRANCH"
  fi
else
  echo "No changes to commit."
fi
