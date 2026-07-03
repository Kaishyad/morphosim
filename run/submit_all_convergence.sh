#!/bin/bash
# Submit one convergence-check job per model, then a single merge+push job
# that runs afterwards.
#
# Usage:
#   ./submit_all_convergence.sh [scenario] [max_trees]
# Examples:
#   ./submit_all_convergence.sh nt 300
#   ./submit_all_convergence.sh mk

SCENARIO="${1:-mk}"
MAX_TREES="${2:-}"

JOB_IDS=()

for i in $(seq 1 12); do
  MODEL="model${i}"
  JOBID=$(sbatch --parsable run_convergence.sh "$MAX_TREES" "$SCENARIO" "$MODEL")
  echo "Submitted ${SCENARIO}/${MODEL} as job ${JOBID}"
  JOB_IDS+=("$JOBID")
done

DEPENDENCY=$(IFS=:; echo "afterany:${JOB_IDS[*]}")

MERGE_JOBID=$(sbatch --parsable --dependency="$DEPENDENCY" merge_and_push.sh "$SCENARIO")
echo "Submitted merge+push as job ${MERGE_JOBID} (depends on: ${JOB_IDS[*]})"
