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
#
# fully automates the requeue -> reconverge -> push cycle, end to end, for
# every scenario/model combo listed in results/requeue_list.txt (ran but
# failed convergence) or results/requeue_from_audit.txt (crashed / never
# started). for each affected combo: archives stale output dirs (requeue
# list only), resubmits via slurm/Infer.R, polls squeue until its jobs
# clear, pushes results, then resubmits + merges convergence checking.
# combos run one at a time for the archive/submit steps, but the
# wait/push/converge chains run concurrently in the background.
#
# run this in a screen/tmux session on the login node -- it polls for as
# long as the underlying inference jobs take (hours), so it must survive
# you disconnecting:
#
#   cd "$MORPHOSIM_DIR"
#   screen -S requeue
#   bash slurm/orchestrate_requeue.sh
#   [Ctrl-A D to detach]
#   screen -r requeue     # to reattach later and check progress
#
# progress is also written to logs/orchestrate_requeue_<timestamp>.log.

set -uo pipefail
cd "$MORPHOSIM_DIR"
module load r

LOG="logs/orchestrate_requeue_$(date +%Y%m%d_%H%M%S).log"
mkdir -p logs
exec > >(tee -a "$LOG") 2>&1

echo "=== $(date '+%Y-%m-%d %H:%M:%S') : starting requeue orchestration ==="
echo "Log: $LOG"

POLL_INTERVAL=300  # seconds between queue checks (5 min)

# the requeue lists live in the-matrix's results/ dir, not morphosim's --
# OutputDir() in R resolves to dirname(getwd())/the-matrix (see
# R/core/_setup.R: ntOutDir). resolved the same way here rather than
# hardcoded, so this stays correct if _setup.R ever changes.
MATRIX_DIR="$(dirname "$(pwd)")/the-matrix"
REQUEUE_LIST="$MATRIX_DIR/results/requeue_list.txt"
REQUEUE_AUDIT="$MATRIX_DIR/results/requeue_from_audit.txt"
echo "Resolved the-matrix results dir: $MATRIX_DIR/results"

# step 1: archive stale outputs for convergence-failed cells
if [ -f "$REQUEUE_LIST" ] && grep -qv '^#' "$REQUEUE_LIST"; then
  echo ""
  echo "--- Archiving stale outputs for $REQUEUE_LIST entries ---"
  Rscript run/requeue/requeue_failed.R --run
else
  echo ""
  echo "No $REQUEUE_LIST (or it's empty/comment-only) -- skipping archive step."
fi

# step 2: collect every affected scenario/model combo from both lists
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

# prioritize model9 first, then model12, so Infer.R's self-imposed
# 70-concurrent-job cap fills with those combos first
PRIORITY_FILE=$(mktemp)
grep -P '\tmodel9$' "$COMBO_FILE" > "$PRIORITY_FILE" || true
grep -P '\tmodel12$' "$COMBO_FILE" >> "$PRIORITY_FILE" || true
grep -v -P '\tmodel(9|12)$' "$COMBO_FILE" >> "$PRIORITY_FILE" || true
mv "$PRIORITY_FILE" "$COMBO_FILE"

echo ""
echo "Combos reordered (model9 first, model12 second):"
cat "$COMBO_FILE"

# step 3: submit every combo up front, back-to-back, no waiting
while IFS=$'\t' read -r SCENARIO MODEL; do
  echo ""
  echo "=== $(date '+%Y-%m-%d %H:%M:%S') : submitting $SCENARIO/$MODEL ==="
  echo "--- Submitting via Infer.R (self-capped at 70 concurrent jobs) ---"
  Rscript slurm/Infer.R --run --scenario "$SCENARIO" --model "$MODEL"
done < "$COMBO_FILE"

# steps 4-6: wait/push/converge per combo, running concurrently. each
# combo's chain runs in its own background subshell so combos don't block
# each other -- only that combo's own squeue wait delays its own push.
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
