#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --mem=8G
#SBATCH --time=00:30:00
#SBATCH -p shared
#SBATCH --job-name=viz
#SBATCH --output=/nobackup/djfb16/morphosim/logs/viz_%j.out
#SBATCH --error=/nobackup/djfb16/morphosim/logs/viz_%j.err

# Usage: sbatch slurm/run_viz.sh
# Runs the viz/ suite and pushes the resulting figures to the-matrix.
# No git pull, no rebase, no retry loop -- just runs and pushes what it made.
# If the push fails (e.g. someone else pushed in the meantime), it prints
# the error and stops; push manually from the-matrix if that happens.
#
# DEPENDENCY: viz/07_cross_metric_analysis.R (part of the suite below)
# reads results/cross_metric_*.rds, which only exist once
# slurm/run_cross_metric_analysis.sh has completed. Don't just `sbatch` this
# on its own the first time -- chain it:
#   jid=$(sbatch --parsable slurm/run_cross_metric_analysis.sh)
#   sbatch --dependency=afterok:$jid slurm/run_viz.sh
# After that first run, cross_metric_gridcell.rds etc. persist on disk, so
# plain `sbatch slurm/run_viz.sh` is fine again until you have new upstream
# results worth re-running cross_metric_analysis for.

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