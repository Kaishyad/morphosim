#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --mem=16G
#SBATCH --time=4:00:00
#SBATCH -p shared
#SBATCH --job-name=tree_accuracy
#SBATCH --output=/nobackup/djfb16/morphosim/logs/tree_accuracy.out
#SBATCH --error=/nobackup/djfb16/morphosim/logs/tree_accuracy.err



cd /nobackup/djfb16/morphosim
Rscript run/tree_accuracy.R --scenario mk --model model1

cd /nobackup/djfb16/the-matrix
git add results/tree_accuracy_summary.rds results/tree_accuracy_per_rep.rds
git commit -m "Tree accuracy: mk model1"
git push origin main
