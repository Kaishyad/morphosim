#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --mem=8G
#SBATCH --time=00:30:00
#SBATCH -p shared
#SBATCH --job-name=viz
#SBATCH --output=/nobackup/djfb16/morphosim/logs/viz_%j.out
#SBATCH --error=/nobackup/djfb16/morphosim/logs/viz_%j.err

#Runs the viz  and pushes the resulting figures to the-matrix

module load r

MORPHOSIM=/nobackup/djfb16/morphosim
MATRIX=/nobackup/djfb16/the-matrix

cd $MORPHOSIM
echo "=== $(date '+%Y-%m-%d %H:%M:%S') starting viz suite ==="
Rscript viz/run_all.R
echo "=== $(date '+%Y-%m-%d %H:%M:%S') finished viz suite ==="

cd $MATRIX
git add figures/
git commit -m "Update viz figures ($(date '+%Y-%m-%d %H:%M'))" || echo "Nothing to commit."
git push origin main

echo "All done at $(date)"