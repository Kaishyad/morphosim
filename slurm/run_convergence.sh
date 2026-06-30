#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --mem=8G
#SBATCH --time=12:00:00
#SBATCH -p shared
#SBATCH --job-name=convergence
#SBATCH --output=/nobackup/djfb16/morphosim/logs/convergence.out
#SBATCH --error=/nobackup/djfb16/morphosim/logs/convergence.err

module load r

cd /nobackup/djfb16/morphosim

for model in model1 model2 model3 model4 model5 model6 model7 model8 model9 model10 model11 model12; do
  Rscript run/check_convergence.R --scenario mk --model $model
done

cd /nobackup/djfb16/the-matrix
git add results/convergence_summary.rds results/requeue_list.txt
git commit -m "Convergence check: mk all models"
git push origin main