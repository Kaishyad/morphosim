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
#bash push_imputation_when_done.sh <scenario> <model>
#
# Same idea as push_when_done.sh, but for imputation output specifically:
#   - reads from results_imputation/ (kept fully separate from results/,
#     never touches your normal inference output)
#   - adds ONLY the files actually needed (6 standard inference-style files
#     + 4 .states files used by ScoreImputation()) -- explicitly, by name,
#     so .ckp checkpoint files (large, only needed to resume an interrupted
#     run, not needed once it's finished) never get pushed regardless of
#     whether they happen to be gitignored.

SCENARIO="$1"
MODEL="$2"

if [ -z "$SCENARIO" ] || [ -z "$MODEL" ]; then
  echo "Usage: bash push_imputation_when_done.sh <mk|nt> <modelN>"
  exit 1
fi

cd "$MATRIX_DIR"
git checkout "$BRANCH"

FILES=(
  "imp_${MODEL}_run_1.log"
  "imp_${MODEL}_run_2.log"
  "imp_${MODEL}.p_run_1.log"
  "imp_${MODEL}.p_run_2.log"
  "imp_${MODEL}_run_1.tar.gz"
  "imp_${MODEL}_run_2.tar.gz"
  "imp_neo_run_1.states"
  "imp_neo_run_2.states"
  "imp_trans_run_1.states"
  "imp_trans_run_2.states"
)

for tl in 1.00 1.50 2.50 5.00; do

  if [ "$SCENARIO" == "mk" ]; then
    for gl in 0.10 0.25 0.50 1.00; do
      for c in 25 50 100 200; do
        grid="tl${tl}_gl${gl}_c${c}"
        for f in "${FILES[@]}"; do
          git add "results_imputation/${SCENARIO}/${grid}"/*/"${MODEL}/${f}" 2>/dev/null
        done
      done
    done
  else
    for gl in 0.10 0.25 0.50 1.00; do
      for pr in 1.00 2.50 5.00; do
        for c in 25 50 100 200; do
          grid="tl${tl}_gl${gl}_pr${pr}_c${c}"
          for f in "${FILES[@]}"; do
            git add "results_imputation/${SCENARIO}/${grid}"/*/"${MODEL}/${f}" 2>/dev/null
          done
        done
      done
    done
  fi

  git commit -m "imputation: ${SCENARIO} ${MODEL} tl${tl} (all gl/pr/c)" 2>/dev/null || true
  git push origin "$BRANCH"
  echo "Pushed imputation tl${tl} for ${SCENARIO} ${MODEL}"

done

echo "All done for ${SCENARIO} ${MODEL} (imputation)."
