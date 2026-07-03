#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --mem=4G
#SBATCH --time=01:00:00
#SBATCH -p shared
#SBATCH --job-name=merge_convergence
#SBATCH --output=/nobackup/djfb16/morphosim/logs/merge_%j.out
#SBATCH --error=/nobackup/djfb16/morphosim/logs/merge_%j.err

module load r

SCENARIO="${1:-}"

cd /nobackup/djfb16/morphosim
if [ -n "$SCENARIO" ]; then
  Rscript run/merge_convergence.R --scenario "$SCENARIO"
else
  Rscript run/merge_convergence.R
fi

cd /nobackup/djfb16/the-matrix
git add results/convergence_summary.rds results/requeue_list.txt

if ! git diff --cached --quiet; then
  git pull --rebase origin main
  if git push origin main; then
    echo "Pushed merged convergence results."
  else
    echo "WARNING: push failed. Push manually with:"
    echo "  cd /nobackup/djfb16/the-matrix && git push origin main"
  fi
else
  echo "No changes to commit."
fi
