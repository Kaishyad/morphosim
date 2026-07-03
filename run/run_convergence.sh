#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --mem=8G
#SBATCH --time=06:00:00
#SBATCH -p shared
#SBATCH --job-name=convergence
#SBATCH --output=/nobackup/djfb16/morphosim/logs/convergence_%j.out
#SBATCH --error=/nobackup/djfb16/morphosim/logs/convergence_%j.err

module load r

cd /nobackup/djfb16/morphosim

# Usage: sbatch run_convergence.sh [max_trees] [scenario] [model]
# Examples:
#   sbatch run_convergence.sh 300 nt model1
#   sbatch run_convergence.sh 300 mk model4
#
# NOTE: no git push here anymore. When --model is set, check_convergence.R
# writes to a per-model file (results/convergence_summary_<scenario>_<model>.rds)
# so concurrent per-model jobs can't race on one shared file. After all model
# jobs for a scenario finish, run merge_and_push.sh once to combine + push.

MAX_TREES_ARG=""
if [ -n "$1" ]; then
  MAX_TREES_ARG="--max-trees $1"
fi

SCENARIO="${2:-mk}"
MODEL="${3:-}"

MODEL_ARG=""
if [ -n "$MODEL" ]; then
  MODEL_ARG="--model $MODEL"
fi

echo "=== $(date '+%Y-%m-%d %H:%M:%S') starting ${SCENARIO}/${MODEL:-all} ==="
Rscript run/check_convergence.R --scenario $SCENARIO $MODEL_ARG $MAX_TREES_ARG
echo "=== $(date '+%Y-%m-%d %H:%M:%S') finished ${SCENARIO}/${MODEL:-all} ==="
