#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --mem=8G
#SBATCH --time=12:00:00
#SBATCH -p shared
#SBATCH --job-name=convergence
#SBATCH --output=/nobackup/djfb16/morphosim/logs/convergence.out
#SBATCH --error=/nobackup/djfb16/morphosim/logs/convergence.err

cd /nobackup/djfb16/morphosim

for scenario in mk nt; do
  for model in model1 model2 model3; do
    Rscript run/check_convergence.R --scenario $scenario --model $model
  done
done

cd /nobackup/djfb16/the-matrix
git add results/convergence_summary.rds results/requeue_list.txt
git commit -m "Convergence check: mk+nt model1-3"
git push origin main