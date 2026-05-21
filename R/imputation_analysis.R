# imputation_analysis.R
# NEW file for nt-sim project.
#
# Top-level wrapper that applies imputation accuracy scoring across the full
# parameter grid and all 12 inference models, then performs pairwise Wilcoxon
# signed-rank tests versus the Mk baseline (Model 1).
#
# Workflow:
#   1. Iterate over all (simID, modelID) combinations with completed inference.
#   2. Call Imputation.R::ImputationForReplicate() for each.
#   3. Pool results with the supervisor's simFuncsImp.R .PoolRuns() and .MeanAcc().
#   4. Run pairwise Wilcoxon tests (Models 2-12 vs Model 1) within each grid cell.
#   5. Save aggregated accuracy data frame and Wilcoxon results as .rds files.
#
# Dissertation section: 6.3 Imputation accuracy
