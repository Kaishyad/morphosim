#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --mem=8G
#SBATCH --time=02:00:00
#SBATCH -p shared
#SBATCH --job-name=model_comparison
#SBATCH --output=/nobackup/djfb16/morphosim/logs/model_comparison_%j.out
#SBATCH --error=/nobackup/djfb16/morphosim/logs/model_comparison_%j.err



module load r

cd /nobackup/djfb16/morphosim
echo "=== $(date '+%Y-%m-%d %H:%M:%S') starting model_comparison ==="
Rscript run/model_comparison.R
echo "=== $(date '+%Y-%m-%d %H:%M:%S') finished model_comparison ==="

cd /nobackup/djfb16/the-matrix
git add results/model_comparison_ranking.csv \
        results/model_comparison_friedman.csv \
        results/model_comparison_pairwise_mk.csv \
        results/model_comparison_pairwise_nt.csv \
        results/model_comparison_scenario_contrast.csv

if ! git diff --cached --quiet; then
  git commit -m "model_comparison: mk/nt tables $(date '+%Y-%m-%d %H:%M')"
  git pull --rebase origin main
  if git push origin main; then
    echo "Pushed model comparison results."
  else
    echo "WARNING: push failed. Push manually with:"
    echo "  cd /nobackup/djfb16/the-matrix && git push origin main"
  fi
else
  echo "No changes to commit."
fi
