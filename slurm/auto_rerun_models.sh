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
# fully automates: rerun inference for a set of models (both scenarios) ->
# push -> full downstream analysis pipeline -> push. no manual steps once
# started.
#
#   bash slurm/auto_rerun_models.sh model7 model9 model10 model12
#   bash slurm/auto_rerun_models.sh              # defaults to the 4 above
#
# in order: deletes old inference output dirs for these models (both
# scenarios) so JobLogsComplete() doesn't skip them; submits inference via
# Infer.R (self-throttled at 70 concurrent jobs); polls squeue until those
# jobs clear; pushes results per scenario/model; submits convergence checks
# scoped to these models then merges + pushes; submits tree_accuracy +
# known_answer scoped to these models, merges + pushes both; submits
# validate_cgr, gam_threshold, model_comparison, cross_metric_analysis on
# the full grid (they compare across all 12 models by design, and are cheap
# since they read pre-computed summaries, not raw mcmc output); finally
# submits run_viz.sh to refresh figures. steps 5-8 mirror
# submit_pipeline.sh's dependency graph, just built from a job-id chain here
# instead of a hardcoded CONV_JOB.
#
# run this in a screen/tmux session on the login node -- step 3 alone can
# take hours, and the whole thing must survive you disconnecting:
#
#   cd "$MORPHOSIM_DIR"
#   screen -S rerun
#   bash slurm/auto_rerun_models.sh model7 model9 model10 model12
#   [Ctrl-A D to detach]
#   screen -r rerun     # reattach later to check progress
#
# progress is also written to logs/auto_rerun_<timestamp>.log.

set -uo pipefail
cd "$MORPHOSIM_DIR"
module load r

MODELS=("$@")
if [ ${#MODELS[@]} -eq 0 ]; then
  MODELS=(model7 model9 model10 model12)
fi
SCENARIOS=(mk nt)

LOG="logs/auto_rerun_$(date +%Y%m%d_%H%M%S).log"
mkdir -p logs
exec > >(tee -a "$LOG") 2>&1

echo "=== $(date '+%Y-%m-%d %H:%M:%S') : starting auto_rerun_models for: ${MODELS[*]} ==="
echo "Log: $LOG"

# step 1: clear old outputs so Infer.R doesn't skip these models
echo ""
echo "--- Removing old inference outputs for ${MODELS[*]} (both scenarios) ---"
for scenario in "${SCENARIOS[@]}"; do
  for model in "${MODELS[@]}"; do
    n=$(find "$MATRIX_DIR/results/$scenario" -maxdepth 3 -type d -name "$model" 2>/dev/null | wc -l)
    find "$MATRIX_DIR/results/$scenario" -maxdepth 3 -type d -name "$model" -exec rm -rf {} + 2>/dev/null
    echo "  $scenario/$model: removed $n old output dir(s)"
  done
done

# step 2: submit inference (both scenarios, all listed models, one call)
echo ""
echo "--- Submitting inference via Infer.R (self-capped at 70 concurrent jobs) ---"
MODEL_ARGS=()
for model in "${MODELS[@]}"; do
  MODEL_ARGS+=(--model "$model")
done
Rscript slurm/Infer.R --run "${MODEL_ARGS[@]}"

# step 3: poll until every inference job for these models has cleared
echo ""
echo "--- Waiting for inference jobs to clear the queue ---"
PATTERN="^inf_($(IFS='|'; echo "${SCENARIOS[*]}"))_.*_($(IFS='|'; echo "${MODELS[*]}"))\$"
POLL_INTERVAL=300  # 5 min
while true; do
  N=$(squeue -u "$USER" -h -o '%j' 2>/dev/null | grep -cE "$PATTERN")
  echo "$(date '+%Y-%m-%d %H:%M:%S'): $N inference job(s) still queued/running"
  [ "$N" -eq 0 ] && break
  sleep "$POLL_INTERVAL"
done
echo "Inference finished for ${MODELS[*]}."

# step 4: push inference results
echo ""
echo "--- Pushing inference results to GitHub ---"
for scenario in "${SCENARIOS[@]}"; do
  for model in "${MODELS[@]}"; do
    bash slurm/push_when_done.sh "$scenario" "$model"
  done
done

# step 5: convergence, scoped to these models, both scenarios
echo ""
echo "--- Submitting convergence checks ---"
conv_ids=""
for scenario in "${SCENARIOS[@]}"; do
  for model in "${MODELS[@]}"; do
    jid=$(sbatch --parsable slurm/run_convergence.sh 300 "$scenario" "$model")
    conv_ids="${conv_ids}:${jid}"
    echo "  convergence $scenario/$model: $jid"
  done
done
conv_ids="${conv_ids#:}"
merge_conv_jid=$(sbatch --parsable --dependency=afterany:$conv_ids slurm/merge_and_push.sh)
echo "merge_convergence (merge_and_push.sh): $merge_conv_jid"

# step 6: tree_accuracy + known_answer, scoped, both scenarios
echo ""
echo "--- Submitting tree_accuracy ---"
tree_ids=""
for scenario in "${SCENARIOS[@]}"; do
  for model in "${MODELS[@]}"; do
    jid=$(sbatch --parsable --dependency=afterok:$merge_conv_jid slurm/run_tree_accuracy.sh "$scenario" "$model")
    tree_ids="${tree_ids}:${jid}"
    echo "  tree_accuracy $scenario/$model: $jid"
  done
done
tree_ids="${tree_ids#:}"
merge_tree_jid=$(sbatch --parsable --dependency=afterany:$tree_ids slurm/merge_tree_accuracy.sh)
echo "merge_tree_accuracy: $merge_tree_jid"

echo ""
echo "--- Submitting known_answer ---"
ka_ids=""
for scenario in "${SCENARIOS[@]}"; do
  for model in "${MODELS[@]}"; do
    jid=$(sbatch --parsable --dependency=afterok:$merge_conv_jid slurm/run_known_answer.sh "$scenario" "$model")
    ka_ids="${ka_ids}:${jid}"
    echo "  known_answer $scenario/$model: $jid"
  done
done
ka_ids="${ka_ids#:}"
merge_ka_jid=$(sbatch --parsable --dependency=afterany:$ka_ids slurm/merge_known_answer.sh)
echo "merge_known_answer: $merge_ka_jid"

# step 7: whole-grid comparisons (no per-model scoping available)
echo ""
echo "--- Submitting validate_cgr, gam_threshold, model_comparison, cross_metric ---"
cgr_jid=$(sbatch --parsable --dependency=afterok:$merge_conv_jid slurm/run_validate_cgr.sh)
echo "validate_cgr: $cgr_jid"

gam_mk_jid=$(sbatch --parsable --dependency=afterok:$merge_tree_jid slurm/run_gam_threshold.sh mk)
gam_nt_jid=$(sbatch --parsable --dependency=afterok:$merge_tree_jid slurm/run_gam_threshold.sh nt)
echo "gam_threshold mk: $gam_mk_jid | nt: $gam_nt_jid"

mc_jid=$(sbatch --parsable --dependency=afterok:$merge_tree_jid slurm/run_model_comparison.sh)
echo "model_comparison: $mc_jid"

cross_jid=$(sbatch --parsable --dependency=afterok:$merge_tree_jid:$merge_ka_jid:$cgr_jid slurm/run_cross_metric_analysis.sh)
echo "cross_metric_analysis: $cross_jid"

# step 8: figures, after everything else
viz_jid=$(sbatch --parsable --dependency=afterok:$cross_jid:$gam_mk_jid:$gam_nt_jid:$mc_jid slurm/run_viz.sh)
echo "viz: $viz_jid"

echo ""
echo "=== $(date '+%Y-%m-%d %H:%M:%S') : all done submitting. Everything from here runs and pushes on its own. ==="
echo "Watch progress with: squeue -u $USER -o \"%.10i %.20j %.10T %.10M %.6D %E\""
echo "The %E column shows what each job is waiting on."
