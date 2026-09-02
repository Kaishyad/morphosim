#!/bin/bash
# under sbatch, slurm copies this script into a job-specific spool directory
# before running it, so BASH_SOURCE no longer points at its real repo
# location and config.sh would fail to source. SLURM_SUBMIT_DIR is the
# directory sbatch was run from, which is what we want; fall back to
# BASH_SOURCE resolution when this script is run directly (not via sbatch).
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
  # count completed jobs
  DONE=$(find $MATRIX/results/$SCENARIO -name "${MODEL}_run_1.log" 2>/dev/null | wc -l)

  # count running/pending jobs in the slurm queue
  RUNNING=$(squeue -u $USER -h 2>/dev/null | grep "inf_${SCENARIO}" | grep " R " | wc -l)
  PENDING=$(squeue -u $USER -h 2>/dev/null | grep "inf_${SCENARIO}" | grep " PD " | wc -l)

  # count any that errored
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

  sleep 300  # check every 5 minutes
done
