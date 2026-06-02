#!/bin/bash
# Waits until all NT simulations are complete, then pushes to the-matrix.
#
# Run in a screen session alongside Simulate.R:
#   screen -S push_watcher
#   bash slurm/push_when_done.sh
#
# To watch Mk instead, change SCENARIO to "mk".
# To watch both, run two separate screen sessions with different SCENARIO values.

MATRIX=/nobackup/djfb16/the-matrix
SCENARIO=nt
EXPECTED=6400   # 64 grid cells x 100 replicates

echo "Watching for $EXPECTED neo.nex files in $MATRIX/simulations/$SCENARIO..."

while true; do
  COUNT=$(find $MATRIX/simulations/$SCENARIO -name "neo.nex" 2>/dev/null | wc -l)
  echo "$(date): $COUNT / $EXPECTED complete"

  if [ "$COUNT" -ge "$EXPECTED" ]; then
    echo "All simulations complete. Pushing to the-matrix..."
    cd $MATRIX
    git add simulations/$SCENARIO/
    git commit -m "Add $SCENARIO simulation outputs ($(date))"
    git pull origin main --rebase
    git push origin main
    echo "Push complete."
    break
  fi

  sleep 300  # check every 5 minutes
done
