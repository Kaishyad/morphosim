#!/bin/bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.sh"
#bash submit_pipeline.sh   # uses CONV_JOB=17872509 below
#bash submit_pipeline.sh 17872509   # or pass the convergence job ID explicitly
set -e
cd "$MORPHOSIM_DIR"
CONV_JOB="${1:-17936992}"
# model12 excluded -- its final jobs keep cancelling on submit. Add it back
# once a full run actually completes (640/640 mk, 1920/1920 nt).
MODELS=(model1 model2 model3 model4 model5 model6 model7 model8 model9 model10 model11)
SCENARIOS=(mk nt)
echo "Chaining everything after convergence job $CONV_JOB"
echo ""
#merge + push convergence results.
if squeue -h -j "$CONV_JOB" 2>/dev/null | grep -q .; then
  echo "Job $CONV_JOB is still live in the scheduler -- will wait for it."
  merge_conv_jid=$(sbatch --parsable --dependency=afterok:$CONV_JOB slurm/merge_and_push.sh)
else
  echo "Job $CONV_JOB is no longer tracked by the scheduler (already finished a while ago) -- submitting step 0 immediately."
  merge_conv_jid=$(sbatch --parsable slurm/merge_and_push.sh)
fi
echo "[0] merge_convergence (merge_and_push.sh): $merge_conv_jid"
# tree accuracy 
tree_all_ids=""
for scenario in "${SCENARIOS[@]}"; do
  for model in "${MODELS[@]}"; do
    jid=$(sbatch --parsable --dependency=afterok:$merge_conv_jid slurm/run_tree_accuracy.sh "$scenario" "$model")
    tree_all_ids="${tree_all_ids}:${jid}"
    echo "[1] tree_accuracy $scenario/$model: $jid"
  done
done
tree_all_ids="${tree_all_ids#:}"
# if one or two models fail
merge_tree_jid=$(sbatch --parsable --dependency=afterany:$tree_all_ids slurm/merge_tree_accuracy.sh)
echo "[1] merge_tree_accuracy: $merge_tree_jid"
echo ""
# known-answer coverage 
ka_all_ids=""
for scenario in "${SCENARIOS[@]}"; do
  for model in "${MODELS[@]}"; do
    jid=$(sbatch --parsable --dependency=afterok:$merge_conv_jid slurm/run_known_answer.sh "$scenario" "$model")
    ka_all_ids="${ka_all_ids}:${jid}"
    echo "[2] known_answer $scenario/$model: $jid"
  done
done
ka_all_ids="${ka_all_ids#:}"
merge_ka_jid=$(sbatch --parsable --dependency=afterany:$ka_all_ids slurm/merge_known_answer.sh)
echo "[2] merge_known_answer: $merge_ka_jid"
echo ""
# CGR/SBC calibration 
cgr_jid=$(sbatch --parsable --dependency=afterok:$merge_conv_jid slurm/run_validate_cgr.sh)
echo "[3] validate_cgr: $cgr_jid"
echo ""
# GAM thresholds 
gam_mk_jid=$(sbatch --parsable --dependency=afterok:$merge_tree_jid slurm/run_gam_threshold.sh mk)
gam_nt_jid=$(sbatch --parsable --dependency=afterok:$merge_tree_jid slurm/run_gam_threshold.sh nt)
echo "[4] gam_threshold mk: $gam_mk_jid"
echo "[4] gam_threshold nt: $gam_nt_jid"
# model comparison
mc_jid=$(sbatch --parsable --dependency=afterok:$merge_tree_jid slurm/run_model_comparison.sh)
echo "[5] model_comparison: $mc_jid"
echo ""
#cross-metric analysis 
cross_jid=$(sbatch --parsable --dependency=afterok:$merge_tree_jid:$merge_ka_jid:$cgr_jid slurm/run_cross_metric_analysis.sh)
echo "[6] cross_metric_analysis: $cross_jid"
echo ""
#figures
viz_jid=$(sbatch --parsable --dependency=afterok:$cross_jid:$gam_mk_jid:$gam_nt_jid:$mc_jid slurm/run_viz.sh)
echo "[7] viz: $viz_jid"
echo ""
echo "All jobs submitted ($(( ${#SCENARIOS[@]} * ${#MODELS[@]} * 2 + 6 )) total)."
echo "Watch progress with: squeue -u $USER -o \"%.10i %.20j %.10T %.10M %.6D %E\""
echo "The %E column shows what each job is waiting on."