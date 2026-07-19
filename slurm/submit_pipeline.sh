#!/bin/bash
# submit_pipeline.sh
#
# Submits the full comparison pipeline as a chain of sbatch jobs with real
# dependencies, so nothing runs before the file(s) it needs actually exist.
# Skips the audit/requeue step (run/audit_incomplete_runs.R) per your
# instruction -- run that separately whenever you're ready to look at it.
#
# Usage:
#   bash submit_pipeline.sh                 # uses CONV_JOB=17872509 below
#   bash submit_pipeline.sh 17872509         # or pass the convergence job ID explicitly
#
# Run this with `bash`, NOT `sbatch` -- it just submits other jobs and exits
# immediately; it doesn't do any of the actual work itself.

set -e
cd /nobackup/djfb16/morphosim

CONV_JOB="${1:-17936992}"

MODELS=(model1 model2 model3 model4 model5 model6 model7 model8 model9 model10 model11 model12)
SCENARIOS=(mk nt)

echo "Chaining everything after convergence job $CONV_JOB"
echo ""

# ---------------------------------------------------------------
# STEP 0: merge + push convergence results.
#
# Despite the filename, slurm/merge_and_push.sh IS the convergence merge
# script (its #SBATCH job-name is literally "merge_convergence") -- it
# wraps run/merge_convergence.R. If job $CONV_JOB was submitted WITHOUT a
# --model flag (i.e. `sbatch slurm/run_convergence.sh` or
# `sbatch slurm/run_convergence.sh 300` with no scenario/model), it already
# writes straight to the combined results/convergence_summary.rds and
# pushes it itself when it finishes -- this step is then a no-op, which is
# fine: run/merge_convergence.R de-duplicates on
# scenario|gridTag|repID|modelID (keeping the newest), so it's always safe
# to run again. If $CONV_JOB WAS a per-model run, this step is what
# actually combines it with everything else and pushes -- so either way,
# always run it before anything below.
#
# NOTE: --dependency=afterok:<id> only works while slurmctld (the live
# scheduler) still knows about that job. Completed jobs get purged from
# the controller a few minutes after finishing (MinJobAge) even though
# `sacct` keeps their history indefinitely -- so if $CONV_JOB already
# finished a while ago, attaching a dependency to it fails immediately
# with "Job dependency problem" even though the job succeeded. We check
# with `squeue` (which only sees live/controller-known jobs) and only
# attach the dependency if it's still there; otherwise we just submit
# straight away, since "the job already finished" and "the dependency is
# already satisfied" mean the same thing here.
# ---------------------------------------------------------------
if squeue -h -j "$CONV_JOB" 2>/dev/null | grep -q .; then
  echo "Job $CONV_JOB is still live in the scheduler -- will wait for it."
  merge_conv_jid=$(sbatch --parsable --dependency=afterok:$CONV_JOB slurm/merge_and_push.sh)
else
  echo "Job $CONV_JOB is no longer tracked by the scheduler (already finished a while ago) -- submitting step 0 immediately."
  merge_conv_jid=$(sbatch --parsable slurm/merge_and_push.sh)
fi
echo "[0] merge_convergence (merge_and_push.sh): $merge_conv_jid"

# ---------------------------------------------------------------
# STEP 1: tree accuracy -- the actual "comparing trees" step.
# One job per (scenario, model) -- run_tree_accuracy.sh always runs in
# single-model mode (its MODEL arg defaults to model1, never "all"), so
# covering all 12 models needs 12 separate submissions per scenario.
# ---------------------------------------------------------------
tree_all_ids=""
for scenario in "${SCENARIOS[@]}"; do
  for model in "${MODELS[@]}"; do
    jid=$(sbatch --parsable --dependency=afterok:$merge_conv_jid slurm/run_tree_accuracy.sh "$scenario" "$model")
    tree_all_ids="${tree_all_ids}:${jid}"
    echo "[1] tree_accuracy $scenario/$model: $jid"
  done
done
tree_all_ids="${tree_all_ids#:}"

# afterany, not afterok: if one or two models fail (e.g. model7's known
# C-stack issue), we still want everything that DID succeed merged rather
# than the merge never running at all.
merge_tree_jid=$(sbatch --parsable --dependency=afterany:$tree_all_ids slurm/merge_tree_accuracy.sh)
echo "[1] merge_tree_accuracy: $merge_tree_jid"
echo ""

# ---------------------------------------------------------------
# STEP 2: known-answer coverage -- independent of tree accuracy, both just
# need convergence_summary.rds. Also one job per (scenario, model).
# ---------------------------------------------------------------
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

# ---------------------------------------------------------------
# STEP 3: CGR/SBC calibration -- optional, one job total (not per-model:
# run_validate_cgr.sh does all 12 models x both scenarios itself), also
# independent, just needs convergence_summary.rds.
# ---------------------------------------------------------------
cgr_jid=$(sbatch --parsable --dependency=afterok:$merge_conv_jid slurm/run_validate_cgr.sh)
echo "[3] validate_cgr: $cgr_jid"
echo ""

# ---------------------------------------------------------------
# STEP 4: GAM thresholds -- needs tree_accuracy_per_rep.rds. One job per
# scenario (baseline bug now fixed -- resolves model1/model8 automatically).
# ---------------------------------------------------------------
gam_mk_jid=$(sbatch --parsable --dependency=afterok:$merge_tree_jid slurm/run_gam_threshold.sh mk)
gam_nt_jid=$(sbatch --parsable --dependency=afterok:$merge_tree_jid slurm/run_gam_threshold.sh nt)
echo "[4] gam_threshold mk: $gam_mk_jid"
echo "[4] gam_threshold nt: $gam_nt_jid"

# ---------------------------------------------------------------
# STEP 5: model comparison -- Friedman + pairwise Wilcoxon. Also just
# needs tree_accuracy_per_rep.rds.
# ---------------------------------------------------------------
mc_jid=$(sbatch --parsable --dependency=afterok:$merge_tree_jid slurm/run_model_comparison.sh)
echo "[5] model_comparison: $mc_jid"
echo ""

# ---------------------------------------------------------------
# STEP 6: cross-metric analysis -- needs tree_accuracy_summary.rds,
# convergence_summary.rds, known_answer_summary.rds, and (if present)
# cgr_coverage.rds.
# ---------------------------------------------------------------
cross_jid=$(sbatch --parsable --dependency=afterok:$merge_tree_jid:$merge_ka_jid:$cgr_jid slurm/run_cross_metric_analysis.sh)
echo "[6] cross_metric_analysis: $cross_jid"
echo ""

# ---------------------------------------------------------------
# STEP 7: figures -- needs cross_metric_analysis and gam_threshold output.
# ---------------------------------------------------------------
viz_jid=$(sbatch --parsable --dependency=afterok:$cross_jid:$gam_mk_jid:$gam_nt_jid:$mc_jid slurm/run_viz.sh)
echo "[7] viz: $viz_jid"

echo ""
echo "All jobs submitted ($(( ${#SCENARIOS[@]} * ${#MODELS[@]} * 2 + 6 )) total)."
echo "Watch progress with: squeue -u $USER -o \"%.10i %.20j %.10T %.10M %.6D %E\""
echo "The %E column shows what each job is waiting on."
