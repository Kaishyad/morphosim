#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --mem=8G
#SBATCH --time=2:00:00
#SBATCH -p shared
#SBATCH --job-name=known_answer
#SBATCH --output=logs/known_answer_%j.out
#SBATCH --error=logs/known_answer_%j.err


source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.sh"
SCENARIO="${1:-mk}"
MODEL="${2:-model1}"

module load r

cd "$MORPHOSIM_DIR"
echo "=== $(date '+%Y-%m-%d %H:%M:%S') starting known_answer ${SCENARIO}/${MODEL} ==="
Rscript run/known_answer/known_answer.R --scenario $SCENARIO --model $MODEL
echo "=== $(date '+%Y-%m-%d %H:%M:%S') finished known_answer ${SCENARIO}/${MODEL} ==="
