#!/bin/bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.sh"
# auto_imputation.sh
#
# Fully automated, first-time-ever imputation run across all 12 models,
# both scenarios. No manual steps once it's started.
#
# Usage:
#   bash slurm/auto_imputation.sh
#
# What it does, in order:
#   1. Masks 10% of observed characters in every replicate (both scenarios),
#      writing imp_neo.nex/imp_trans.nex next to the real data. This step
#      has no dependency on inference and starts immediately.
#   2. Submits imputation inference (imp-mc3.Rev) for all 12 models, both
#      scenarios, via slurm/Infer.R --run --imputation. Also no dependency
#      on your normal inference -- it's a separate MCMC run.
#   3. Polls squeue every 5 min until all those imputation jobs clear.
#   4. Pushes imputation results to GitHub (same directories as normal
#      inference output, just imp_-prefixed files -- push_when_done.sh
#      handles both automatically).
#   5. Waits for STANDARD (non-imputation) inference to show every one of
#      the 12 models as converged in convergence_summary.rds. This is a
#      real dependency: run/imputation/imputation_analysis.R only scores
#      replicates that already appear there with pass = TRUE. If you're
#      also running auto_rerun_models.sh for some models, this step just
#      waits on it -- nothing to do on your end.
#   6. Once all 12 models are represented, submits one batch job that runs
#      scoring -> correlation -> plots -> pushes the results. (These three
#      R scripts don't submit their own sbatch jobs like the rest of the
#      pipeline does, so this script wraps them in one so nothing heavy
#      runs on the login node.)
#
# RUN THIS IN A screen/tmux SESSION ON THE LOGIN NODE -- steps 3 and 5 can
# take hours, and it must survive you disconnecting:
#
#   cd "$MORPHOSIM_DIR"
#   screen -S imputation
#   bash slurm/auto_imputation.sh
#   [Ctrl-A D to detach]
#   screen -r imputation     # reattach later to check progress
#
# Progress is also written to logs/auto_imputation_<timestamp>.log.

set -uo pipefail
export MORPHOSIM_DIR MATRIX_DIR BRANCH
cd "$MORPHOSIM_DIR"
module load r

MODELS=(model1 model2 model3 model4 model5 model6 model7 model8 model9 model10 model11 model12)
SCENARIOS=(mk nt)
POLL_INTERVAL=300  # 5 min

LOG="logs/auto_imputation_$(date +%Y%m%d_%H%M%S).log"
mkdir -p logs
exec > >(tee -a "$LOG") 2>&1

echo "=== $(date '+%Y-%m-%d %H:%M:%S') : starting auto_imputation (all 12 models, both scenarios) ==="
echo "Log: $LOG"

# --- Step 1: mask the data (no dependency, runs immediately) -----------
echo ""
echo "--- Masking observed characters (10% default) ---"
Rscript run/imputation/mask_replicates.R --run

# --- Step 2: submit imputation inference, all models, both scenarios ---
echo ""
echo "--- Submitting imputation inference via Infer.R --imputation ---"
Rscript slurm/Infer.R --run --imputation

# --- Step 3: poll until every imputation job has cleared ---------------
echo ""
echo "--- Waiting for imputation inference jobs to clear the queue ---"
while true; do
  N=$(squeue -u "$USER" -h -o '%j' 2>/dev/null | grep -cE '^impinf_')
  echo "$(date '+%Y-%m-%d %H:%M:%S'): $N imputation inference job(s) still queued/running"
  [ "$N" -eq 0 ] && break
  sleep "$POLL_INTERVAL"
done
echo "Imputation inference finished for all models."

# --- Step 4: push imputation results ------------------------------------
echo ""
echo "--- Pushing imputation results to GitHub ---"
for scenario in "${SCENARIOS[@]}"; do
  for model in "${MODELS[@]}"; do
    bash slurm/push_when_done.sh "$scenario" "$model"
  done
done

# --- Step 5: wait for STANDARD inference to show all 12 models converged
echo ""
echo "--- Waiting for standard convergence_summary.rds to cover all 12 models ---"
echo "(This is the real dependency: imputation scoring only uses replicates"
echo " that already show pass = TRUE there. If model5/7/8/9/10/12 are still"
echo " being rerun by auto_rerun_models.sh, this just waits on that.)"
while true; do
  git -C "$MATRIX_DIR" pull origin "$BRANCH" --quiet 2>/dev/null

  READY=$(Rscript -e '
    conv_rds <- file.path(Sys.getenv("MATRIX_DIR"), "results", "convergence_summary.rds")
    if (!file.exists(conv_rds)) { cat("0"); quit(save = "no") }
    conv <- readRDS(conv_rds)
    passed <- unique(conv$modelID[conv$pass])
    needed <- paste0("model", 1:12)
    missing <- setdiff(needed, passed)
    if (length(missing) == 0) { cat("1") } else {
      cat("0")
      message("Still missing convergence data for: ", paste(missing, collapse = ", "))
    }
  ' 2>&1)
  STATUS=$(echo "$READY" | tail -1)

  echo "$(date '+%Y-%m-%d %H:%M:%S'): $READY"
  [ "$STATUS" = "1" ] && break
  sleep "$POLL_INTERVAL"
done
echo "All 12 models represented in convergence_summary.rds."

# --- Step 6: score, correlate, plot, push -- as one batch job -----------
echo ""
echo "--- Submitting imputation scoring/correlation/plots as a batch job ---"
score_jid=$(sbatch --parsable --job-name=imputation_score \
  --output=logs/imputation_score_%j.out --error=logs/imputation_score_%j.err \
  --wrap="
    source slurm/config.sh
    cd \"\$MORPHOSIM_DIR\"
    module load r
    set -e
    Rscript run/imputation/imputation_analysis.R
    Rscript run/correlation/correlation_analysis.R --scenario mk
    Rscript run/correlation/correlation_analysis.R --scenario nt
    Rscript run/imputation/imputation_accuracy_plots.R
    cd \"\$MATRIX_DIR\"
    git checkout \"\$BRANCH\"
    git add results/imputation_accuracy.rds results/imputation_accuracy_per_rep.rds \
            results/imputation_wilcoxon.rds figures/imputation/ 2>/dev/null
    git commit -m \"imputation: scoring + correlation + plots \$(date '+%Y-%m-%d')\" || true
    git pull --rebase origin \"\$BRANCH\"
    git push origin \"\$BRANCH\"
  ")
echo "imputation scoring/plots job: $score_jid"

echo ""
echo "=== $(date '+%Y-%m-%d %H:%M:%S') : all done submitting. Job $score_jid will finish and push on its own. ==="
echo "Watch it with: squeue -u $USER -o \"%.10i %.20j %.10T %.10M %.6D %E\""
echo "Or once it's done: tail logs/imputation_score_${score_jid}.out"
