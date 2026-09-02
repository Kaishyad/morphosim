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
# bash push_when_done.sh <scenario> <model>

SCENARIO="$1"
MODEL="$2"

if [ -z "$SCENARIO" ] || [ -z "$MODEL" ]; then
  echo "Usage: bash push_when_done.sh <mk|nt> <modelN>"
  exit 1
fi

cd "$MATRIX_DIR"

FILES=(
  "${MODEL}_run_1.log"
  "${MODEL}_run_2.log"
  "${MODEL}.p_run_1.log"
  "${MODEL}.p_run_2.log"
  "${MODEL}_run_1.tar.gz"
  "${MODEL}_run_2.tar.gz"
)

for tl in 1.00 1.50 2.50 5.00; do

  if [ "$SCENARIO" == "mk" ]; then
    for gl in 0.10 0.25 0.50 1.00; do
      for c in 25 50 100 200; do
        grid="tl${tl}_gl${gl}_c${c}"
        for f in "${FILES[@]}"; do
          git add "results/${SCENARIO}/${grid}"/*/"${MODEL}/${f}" 2>/dev/null
        done
      done
    done
  else
    for gl in 0.10 0.25 0.50 1.00; do
      for pr in 1.00 2.50 5.00; do
        for c in 25 50 100 200; do
          grid="tl${tl}_gl${gl}_pr${pr}_c${c}"
          for f in "${FILES[@]}"; do
            git add "results/${SCENARIO}/${grid}"/*/"${MODEL}/${f}" 2>/dev/null
          done
        done
      done
    done
  fi

  # one commit per tl block, not per grid cell
  git commit -m "${SCENARIO} ${MODEL} tl${tl} (all gl/pr/c)" 2>/dev/null || true
  git push origin "$BRANCH"
  echo "Pushed tl${tl} for ${SCENARIO} ${MODEL}"

done

echo "All done for ${SCENARIO} ${MODEL}."
