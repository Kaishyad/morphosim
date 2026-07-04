#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --mem=8G
#SBATCH --time=2:00:00
#SBATCH -p shared
#SBATCH --job-name=known_answer
#SBATCH --output=/nobackup/djfb16/morphosim/logs/known_answer_%j.out
#SBATCH --error=/nobackup/djfb16/morphosim/logs/known_answer_%j.err

# Usage: sbatch slurm/run_known_answer.sh [scenario] [model]
# Examples:
#   sbatch slurm/run_known_answer.sh mk model4
#   sbatch slurm/run_known_answer.sh nt model8
# No git push here — run slurm/merge_known_answer.sh after all model jobs finish.

SCENARIO="${1:-mk}"
MODEL="${2:-model1}"

module load r

cd /nobackup/djfb16/morphosim
echo "=== $(date '+%Y-%m-%d %H:%M:%S') starting known_answer ${SCENARIO}/${MODEL} ==="
Rscript run/known_answer.R --scenario $SCENARIO --model $MODEL
echo "=== $(date '+%Y-%m-%d %H:%M:%S') finished known_answer ${SCENARIO}/${MODEL} ==="
