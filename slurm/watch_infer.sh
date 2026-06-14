#!/bin/bash

# Watch inference progress for a given scenario and model.
# Run in a screen session:
#   screen -S watch_infer
#   bash slurm/watch_infer.sh
# Ctrl+A D to detach.
#
# To watch a different scenario/model, edit SCENARIO and MODEL below,
# or run two screen sessions with different values.

MATRIX=/nobackup/djfb16/the-matrix
SCENARIO=mk
MODEL=model1
EXPECTED=6400   # 64 grid cells x 100 replicates

echo "Watching for $EXPECTED completed $MODEL jobs in $MATRIX/results/$SCENARIO..."
echo ""

while true; do
  # Count completed jobs (log file written by RevBayes on completion)
  DONE=$(find $MATRIX/results/$SCENARIO -name "${MODEL}_run_1.log" 2>/dev/null | wc -l)

  # Count running jobs in slurm queue
  RUNNING=$(squeue -u $USER -h -n "inf_${SCENARIO}_*_${MODEL}" 2>/dev/null | grep " R " | wc -l)
  PENDING=$(squeue -u $USER -h -n "inf_${SCENARIO}_*_${MODEL}" 2>/dev/null | grep " PD " | wc -l)

  # Count any that errored (non-empty .err files)
  ERRORS=$(find /nobackup/$USER/morphosim/logs -name "inf_${SCENARIO}_*_${MODEL}.err" \
           -newer /nobackup/$USER/morphosim/slurm/Infer.R -size +0c 2>/dev/null | wc -l)

  echo "$(date): $DONE / $EXPECTED complete | Running: $RUNNING | Pending: $PENDING | Errors: $ERRORS"

  if [ "$DONE" -ge "$EXPECTED" ]; then
    echo ""
    echo "All $MODEL inference jobs complete for scenario $SCENARIO!"
    break
  fi

  sleep 300  # check every 5 minutes
done
