#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --mem=8G
#SBATCH --time=04:00:00
#SBATCH -p shared
#SBATCH --job-name=validate_cgr
#SBATCH --output=/nobackup/djfb16/morphosim/logs/validate_cgr_%j.out
#SBATCH --error=/nobackup/djfb16/morphosim/logs/validate_cgr_%j.err

BRANCH="clean-rebuild"

module load r

cd /nobackup/djfb16/morphosim
echo "=== $(date '+%Y-%m-%d %H:%M:%S') starting validate_cgr ==="
Rscript R/validation/validate_cgr.R
echo "=== $(date '+%Y-%m-%d %H:%M:%S') finished validate_cgr ==="

cd /nobackup/djfb16/the-matrix
git checkout "$BRANCH"
git add results/cgr_coverage.rds results/cgr_coverage.csv

if ! git diff --cached --quiet; then
  git commit -m "validate_cgr: coverage results $(date '+%Y-%m-%d %H:%M')"
  git pull --rebase origin "$BRANCH"
  if git push origin "$BRANCH"; then
    echo "Pushed CGR coverage results."
  else
    echo "WARNING: push failed. Push manually with:"
    echo "  cd /nobackup/djfb16/the-matrix && git push origin $BRANCH"
  fi
else
  echo "No changes to commit."
fi
