#!/bin/bash

# Under sbatch, SLURM copies this script into a job-specific spool directory
# before executing it, so ${BASH_SOURCE[0]} no longer points at its real
# location in the repo -- config.sh would silently fail to source (MATRIX_DIR/
# MORPHOSIM_DIR/BRANCH stay unset) and any $MATRIX_DIR-based cd/git command
# later in this script would then operate on the wrong directory. SLURM sets
# SLURM_SUBMIT_DIR to the directory `sbatch` was run from, which is what we
# actually want. Fall back to BASH_SOURCE-based resolution for the case where
# this script is run directly (not via sbatch).
if [ -n "$SLURM_SUBMIT_DIR" ]; then
  SCRIPT_DIR="$SLURM_SUBMIT_DIR/slurm"
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
source "$SCRIPT_DIR/config.sh"
MATRIX="$MATRIX_DIR"
SCENARIO=nt
MODEL=model11
EXPECTED=1920  

echo "Watching for $EXPECTED completed $MODEL jobs in $MATRIX/results/$SCENARIO..."
echo ""

while true; do
  #Count completed jobs 
  DONE=$(find $MATRIX/results/$SCENARIO -name "${MODEL}_run_1.log" 2>/dev/null | wc -l)

  #Count running jobs in slurm queue
  RUNNING=$(squeue -u $USER -h 2>/dev/null | grep "inf_${SCENARIO}" | grep " R " | wc -l)
  PENDING=$(squeue -u $USER -h 2>/dev/null | grep "inf_${SCENARIO}" | grep " PD " | wc -l)

  #Count any that errored 
  ERRORS=$(find $MORPHOSIM_DIR/logs -name "inf_${SCENARIO}_*_${MODEL}.err" \
           -newer $MORPHOSIM_DIR/slurm/Infer.R -size +0c 2>/dev/null | wc -l)

  echo "$(date): $DONE / $EXPECTED complete | Running: $RUNNING | Pending: $PENDING | Errors: $ERRORS"

  if [ "$DONE" -ge "$EXPECTED" ]; then
    echo ""
    echo "All $MODEL inference jobs complete for scenario $SCENARIO!"
    cd "$MATRIX_DIR"
    git checkout "$BRANCH"
    git add results/$SCENARIO/
    git commit -m "Inference: $SCENARIO $MODEL all $EXPECTED results"
    git push origin "$BRANCH"
    echo "Pushed to GitHub."
    break
  fi

  sleep 300  #check every 5 minutes
done
