#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --mem=8G
#SBATCH --time=00:30:00
#SBATCH -p shared
#SBATCH --job-name=check_improvement
#SBATCH --output=/nobackup/djfb16/morphosim/logs/check_improvement_%j.out
#SBATCH --error=/nobackup/djfb16/morphosim/logs/check_improvement_%j.err

module load r
cd /nobackup/djfb16/morphosim
Rscript run/check_improvement_range.R
