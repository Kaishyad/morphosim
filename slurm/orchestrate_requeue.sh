#!/bin/bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.sh"
# orchestrate_requeue.sh
#
# Fully automates the requeue -> reconverge -> push cycle, end to end, for
# every scenario/model combo listed in EITHER:
#   - results/requeue_list.txt        (ran but failed convergence)
#   - results/requeue_from_audit.txt  (crashed / never started)
#
# For each affected (scenario, model) combo, in turn:
#   1. [requeue_list.txt only] archive the stale output dirs so
#      JobLogsComplete() stops skipping them (run/requeue/requeue_failed.R)
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
#   cd "$MORPHOSIM_DIR"
#   screen -S requeue
#   bash slurm/orchestrate_requeue.sh
#   [Ctrl-A D to detach]
#   screen -r requeue     # to reattach later and check progress
#
# Progress is also written to logs/orchestrate_requeue_<timestamp>.log.

set -uo pipefail
cd "$MORPHOSIM_DIR"
module load r

LOG="logs/orchestrate_requeue_$(date +%Y%m%d_%H%M%S).log"
mkdir -p logs
exec > >(tee -a "$LOG") 2>&1

echo "=== $(date '+%Y-%m-%d %H:%M:%S') : starting requeue orchestration ==="
echo "Log: $LOG"

POLL_INTERVAL=300  # seconds between queue checks (5 min)

# The requeue lists live in the-matrix's results/ dir, not morphosim's --
# OutputDir() in R resolves to dirname(getwd())/the-matrix (see
# R/core/_setup.R: ntOutDir). Resolve it the same way here rather than
# hardcoding, so this stays correct if _setup.R ever changes.
MATRIX_DIR="$(dirname "$(pwd)")/the-matrix"
REQUEUE_LIST="$MATRIX_DIR/results/requeue_list.txt"
REQUEUE_AUDIT="$MATRIX_DIR/results/requeue_from_audit.txt"
echo "Resolved the-matrix results dir: $MATRIX_DIR/results"

# --- Step 1: archive stale outputs for convergence-failed cells -----------
if [ -f "$REQUEUE_LIST" ] && grep -qv '^#' "$REQUEUE_LIST"; then
  echo ""
  echo "--- Archiving stale outputs for $REQUEUE_LIST entries ---"
  Rscript run/requeue/requeue_failed.R --run
else
  echo ""
  echo "No $REQUEUE_LIST (or it's empty/comment-only) -- skipping archive step."
fi

# --- Step 2: collect every affected scenario/model combo from both lists --
COMBO_FILE=$(mktemp)
for f in "$REQUEUE_LIST" "$REQUEUE_AUDIT"; do
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

# Prioritize model9 and model12 -- put their combos first so Infer.R's
# self-imposed 70-concurrent-job cap fills with these first, ahead of
# other models' combos further down the file. (Previously this script
# unconditionally skipped model11/model12 as "already run" -- that's no
# longer true for model12 given current pass rates, so that skip is gone.)
PRIORITY_FILE=$(mktemp)
grep -P '\tmodel(9|12)$' "$COMBO_FILE" > "$PRIORITY_FILE" || true
grep -v -P '\tmodel(9|12)$' "$COMBO_FILE" >> "$PRIORITY_FILE" || true
mv "$PRIORITY_FILE" "$COMBO_FILE"

echo ""
echo "Combos reordered (model9/model12 first):"
cat "$COMBO_FILE"

# --- Step 3: submit every combo up front, back-to-back, no waiting --------
while IFS=$'\t' read -r SCENARIO MODEL; do
  echo ""
  echo "=== $(date '+%Y-%m-%d %H:%M:%S') : submitting $SCENARIO/$MODEL ==="
  echo "--- Submitting via Infer.R (self-capped at 70 concurrent jobs) ---"
  Rscript slurm/Infer.R --run --scenario "$SCENARIO" --model "$MODEL"
done < "$COMBO_FILE"

# --- Steps 4-6: wait/push/converge per combo, running concurrently --------
# Each combo's wait-then-push-then-converge chain runs in its own background
# subshell so combos don't block each other -- only the actual squeue wait
# for THAT combo delays ITS OWN push, not the next combo's submission (which
# already happened above) or any other combo's push.
PIDS=()
while IFS=$'\t' read -r SCENARIO MODEL; do
  (
    echo ""
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
  ) &
  PIDS+=($!)
done < "$COMBO_FILE"

rm -f "$COMBO_FILE"

echo ""
echo "=== $(date '+%Y-%m-%d %H:%M:%S') : all combos submitted; waiting for ${#PIDS[@]} background wait/push/converge chains to finish ==="
wait "${PIDS[@]}"
echo ""
echo "=== $(date '+%Y-%m-%d %H:%M:%S') : all combos processed. Final merge+push jobs are queued and will finish/push on their own. ==="
