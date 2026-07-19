#!/bin/bash

MATRIX=/nobackup/djfb16/the-matrix
BRANCH="clean-rebuild"
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
  ERRORS=$(find /nobackup/$USER/morphosim/logs -name "inf_${SCENARIO}_*_${MODEL}.err" \
           -newer /nobackup/$USER/morphosim/slurm/Infer.R -size +0c 2>/dev/null | wc -l)

  echo "$(date): $DONE / $EXPECTED complete | Running: $RUNNING | Pending: $PENDING | Errors: $ERRORS"

  if [ "$DONE" -ge "$EXPECTED" ]; then
    echo ""
    echo "All $MODEL inference jobs complete for scenario $SCENARIO!"
    cd /nobackup/djfb16/the-matrix
    git checkout "$BRANCH"
    git add results/$SCENARIO/
    git commit -m "Inference: $SCENARIO $MODEL all $EXPECTED results"
    git push origin "$BRANCH"
    echo "Pushed to GitHub."
    break
  fi

  sleep 300  #check every 5 minutes
done
