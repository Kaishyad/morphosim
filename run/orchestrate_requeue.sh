#!/bin/bash
# orchestrate_requeue.sh
#
# Fully automates the requeue -> reconverge -> push cycle, end to end, for
# every scenario/model combo listed in EITHER:
#   - results/requeue_list.txt        (ran but failed convergence)
#   - results/requeue_from_audit.txt  (crashed / never started)
#
# For each affected (scenario, model) combo, in turn:
#   1. [requeue_list.txt only] archive the stale output dirs so
#      JobLogsComplete() stops skipping them (run/requeue_failed.R)
#   2. resubmit via slurm/Infer.R --run --scenario S --model M
#      (Infer.R self-caps concurrent jobs at MAX_QUEUE_DEPTH = 70; nothing
#      to change here, it already enforces this)
#   3. poll squeue every 5 min until that combo's jobs have cleared
#   4. push results to GitHub (slurm/push_when_done.sh S M)
#   5. resubmit convergence checking for that combo + merge/push
#      (slurm/run_convergence.sh, slurm/merge_and_push.sh)
#
# Combos are processed one at a time (not in parallel) -- simpler to reason
# about and safer for git pushes than trying to interleave multiple combos'
# pushes. If you have many combos queued this will take a while; that's
# expected, just leave it running.
#
# RUN THIS IN A screen/tmux SESSION ON THE LOGIN NODE -- it polls for as
# long as the underlying inference jobs take (hours), so it must survive
# you disconnecting:
#
#   cd /nobackup/djfb16/morphosim
#   screen -S requeue
#   bash run/orchestrate_requeue.sh
#   [Ctrl-A D to detach]
#   screen -r requeue     # to reattach later and check progress
#
# Progress is also written to logs/orchestrate_requeue_<timestamp>.log.

set -uo pipefail
cd /nobackup/djfb16/morphosim
module load r

LOG="logs/orchestrate_requeue_$(date +%Y%m%d_%H%M%S).log"
mkdir -p logs
exec > >(tee -a "$LOG") 2>&1

echo "=== $(date '+%Y-%m-%d %H:%M:%S') : starting requeue orchestration ==="
echo "Log: $LOG"

POLL_INTERVAL=300  # seconds between queue checks (5 min)

# --- Step 1: archive stale outputs for convergence-failed cells -----------
if [ -f results/requeue_list.txt ] && grep -qv '^#' results/requeue_list.txt; then
  echo ""
  echo "--- Archiving stale outputs for results/requeue_list.txt entries ---"
  Rscript run/requeue_failed.R --run
else
  echo ""
  echo "No results/requeue_list.txt (or it's empty/comment-only) -- skipping archive step."
fi

# --- Step 2: collect every affected scenario/model combo from both lists --
COMBO_FILE=$(mktemp)
for f in results/requeue_list.txt results/requeue_from_audit.txt; do
  [ -f "$f" ] || continue
  grep -v '^#' "$f" | awk -F'\t' 'NF==4 {print $1"\t"$4}'
done | sort -u > "$COMBO_FILE"

if [ ! -s "$COMBO_FILE" ]; then
  echo ""
  echo "No affected scenario/model combos found in either requeue list -- nothing to do."
  rm -f "$COMBO_FILE"
  exit 0
fi

echo ""
echo "Affected scenario/model combos (from requeue_list.txt + requeue_from_audit.txt):"
cat "$COMBO_FILE"

# --- Steps 3-6: process each combo end-to-end, sequentially ---------------
while IFS=$'\t' read -r SCENARIO MODEL; do
  echo ""
  echo "=== $(date '+%Y-%m-%d %H:%M:%S') : processing $SCENARIO/$MODEL ==="

  echo "--- Submitting via Infer.R (self-capped at 70 concurrent jobs) ---"
  Rscript slurm/Infer.R --run --scenario "$SCENARIO" --model "$MODEL"

  echo "--- Waiting for $SCENARIO/$MODEL inference jobs to clear the queue ---"
  while true; do
    N=$(squeue -u "$USER" -h -o '%j' 2>/dev/null | grep -c "^inf_${SCENARIO}_.*_${MODEL}\$")
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $N job(s) still queued/running for $SCENARIO/$MODEL"
    [ "$N" -eq 0 ] && break
    sleep "$POLL_INTERVAL"
  done
  echo "$SCENARIO/$MODEL inference jobs finished."

  echo "--- Pushing $SCENARIO/$MODEL results to GitHub ---"
  bash slurm/push_when_done.sh "$SCENARIO" "$MODEL"

  echo "--- Resubmitting convergence check for $SCENARIO/$MODEL ---"
  CONV_JID=$(sbatch --parsable slurm/run_convergence.sh 300 "$SCENARIO" "$MODEL")
  MERGE_JID=$(sbatch --parsable --dependency=afterany:"$CONV_JID" slurm/merge_and_push.sh "$SCENARIO")
  echo "Convergence job: $CONV_JID | merge+push job: $MERGE_JID (will push convergence_summary.rds + requeue_list.txt when done)"

done < "$COMBO_FILE"

rm -f "$COMBO_FILE"
echo ""
echo "=== $(date '+%Y-%m-%d %H:%M:%S') : all combos processed. Final merge+push jobs are queued and will finish/push on their own. ==="
