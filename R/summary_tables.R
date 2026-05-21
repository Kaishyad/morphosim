# summary_tables.R
# NEW file for nt-sim project.
#
# Aggregates all analysis results into formatted CSV tables ready for import
# into the dissertation (LaTeX or knitr).
#
# Tables to produce (one CSV each):
#   table_convergence.csv  - ESS, R-hat, ASDSF pass rates per model.
#   table_coverage.csv     - Cook-Gelman-Rubin coverage rates (Table 6.1).
#   table_tree_accuracy.csv - Median CID and IQR per model × grid cell.
#   table_imputation.csv   - Mean imputation accuracy and Wilcoxon p-values.
#   table_correlation.csv  - Spearman rho with bootstrap CIs (Table 6.3).
#   table_pps.csv          - PPS adequacy rates per model.
#   table_gam_thresholds.csv - GAM threshold estimates per model × parameter axis.
#
# Dissertation section: Results / Writing
