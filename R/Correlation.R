# Correlation.R
# NEW file for nt-sim project.
#
# Tests whether imputation accuracy is a reliable proxy for topological accuracy
# across the model space (subsidiary research question 1; Spielman & Wilke 2020).
#
# Key functions to implement:
#   SpearmanCorrelation()  - Computes Spearman's rho between per-replicate median
#                            CID and mean imputation accuracy; returns rho and
#                            bootstrap 95% CI via the boot package.
#   CorrelationTest()      - Applies SpearmanCorrelation() for each (model, grid-
#                            cell) combination and collects results.
#   CorrelationSummary()   - Produces a tidy data frame of rho, lower CI, upper CI,
#                            and p-value across all models; formatted for
#                            dissertation Table 6.3.
#
# Used in: analysis/08_correlation.R
# Dissertation section: 6.3 Spearman correlation
