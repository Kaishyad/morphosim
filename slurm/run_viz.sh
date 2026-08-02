#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --mem=8G
#SBATCH --time=00:30:00
#SBATCH -p shared
#SBATCH --job-name=viz
#SBATCH --output=logs/viz_%j.out
#SBATCH --error=logs/viz_%j.err

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.sh"
#Runs the viz and pushes the resulting figures to the-matrix

module load r

MORPHOSIM="$MORPHOSIM_DIR"
MATRIX="$MATRIX_DIR"

cd $MORPHOSIM
echo "=== $(date '+%Y-%m-%d %H:%M:%S') starting viz suite ==="
Rscript run/shared/run_all.R
echo "=== $(date '+%Y-%m-%d %H:%M:%S') finished viz suite ==="

cd $MATRIX
git checkout "$BRANCH"
git add figures/
git commit -m "Update viz figures ($(date '+%Y-%m-%d'))" || echo "Nothing to commit."
git push origin "$BRANCH"

echo "All done at $(date)"
