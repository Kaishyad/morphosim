# correlation_analysis.R
# NEW file for nt-sim project.
#
# Computes Spearman's rank correlation between imputation accuracy and topological
# accuracy (CID) across the model space, with bootstrap confidence intervals.
#
# Workflow:
#   1. Load per-replicate CID summaries (from 05_tree_accuracy.R output).
#   2. Load per-replicate imputation accuracy (from 06_imputation.R output).
#   3. Call Correlation.R::CorrelationSummary() for each model.
#   4. Export tidy data frame as .rds and CSV for dissertation Table 6.3.
#
# Motivated by Spielman & Wilke (2020); bootstrap CIs via the boot package.
#
# Dissertation section: 6.3 Spearman correlation
