#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --mem=8G
#SBATCH --time=2:00:00
#SBATCH -p shared
#SBATCH --job-name=convergence
#SBATCH --output=/nobackup/djfb16/morphosim/logs/convergence.out
#SBATCH --error=/nobackup/djfb16/morphosim/logs/convergence.err

cd /nobackup/djfb16/morphosim
Rscript run/check_convergence.R --scenario mk --model model1

cd /nobackup/djfb16/the-matrix
git add results/convergence_summary.rds results/requeue_list.txt
git commit -m "Convergence check: mk model1"
git push origin main