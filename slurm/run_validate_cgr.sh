#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --mem=8G
#SBATCH --time=04:00:00
#SBATCH -p shared
#SBATCH --job-name=validate_cgr
#SBATCH --output=/nobackup/djfb16/morphosim/logs/validate_cgr_%j.out
#SBATCH --error=/nobackup/djfb16/morphosim/logs/validate_cgr_%j.err

# Usage: sbatch slurm/run_validate_cgr.sh
# Runs all 12 models x both scenarios (mk, nt) in one job -- unlike
# known_answer/tree_accuracy this isn't split per-model, since it reads
# already-merged convergence_summary.rds rather than raw per-model logs,
# so there's no parallel-write race to avoid. Bump --time if the full
# sweep runs long on your grid size; check the .out log's per-model
# timestamps on first run to calibrate.
#
# Requires: results/convergence_summary.rds already merged and current
# (including model7/model9 once those reruns land) -- see run_convergence.sh
# and run/merge_convergence.R.
#
# Pushes results/cgr_coverage.rds and results/cgr_coverage.csv to
# the-matrix on completion.

module load r

cd /nobackup/djfb16/morphosim
echo "=== $(date '+%Y-%m-%d %H:%M:%S') starting validate_cgr ==="
Rscript R/validation/validate_cgr.R
echo "=== $(date '+%Y-%m-%d %H:%M:%S') finished validate_cgr ==="

cd /nobackup/djfb16/the-matrix
git add results/cgr_coverage.rds results/cgr_coverage.csv

if ! git diff --cached --quiet; then
  git commit -m "validate_cgr: coverage results $(date '+%Y-%m-%d %H:%M')"
  git pull --rebase origin main
  if git push origin main; then
    echo "Pushed CGR coverage results."
  else
    echo "WARNING: push failed. Push manually with:"
    echo "  cd /nobackup/djfb16/the-matrix && git push origin main"
  fi
else
  echo "No changes to commit."
fi
