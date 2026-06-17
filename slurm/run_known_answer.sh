#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --mem=8G
#SBATCH --time=2:00:00
#SBATCH -p shared
#SBATCH --job-name=known_answer
#SBATCH --output=/nobackup/djfb16/morphosim/logs/known_answer.out
#SBATCH --error=/nobackup/djfb16/morphosim/logs/known_answer.err

cd /nobackup/djfb16/morphosim
Rscript run/known_answer.R --scenario mk --model model1

cd /nobackup/djfb16/the-matrix
git add results/known_answer_summary.rds results/known_answer_summary.csv
git commit -m "Known answer test: mk model1"
git push origin main
