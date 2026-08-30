# "do models that produce better trees also have better results?"


source("R/core/_setup.R")
source("R/analysis/Correlation.R")   # for SpearmanCorrelation(), reused by CrossMetric.R
source("R/analysis/CrossMetric.R")

results_dir <- file.path(OutputDir(), "results", "cross_metric")
dir.create(results_dir, showWarnings = FALSE, recursive = TRUE)

# Each input file below is owned/written by a different upstream script, so it
# lives in that script's own results subfolder -- NOT in cross_metric's own
# output folder. Map each filename to the folder that actually owns it.
.INPUT_DIR <- function(name) {
  owner <- switch(name,
    "tree_accuracy_summary.rds" = "tree_accuracy",
    "convergence_summary.rds"   = NULL,  # shared top-level file, no subfolder
    "known_answer_summary.rds"  = "known_answer",
    "cgr_coverage.rds"          = "cgr",
    "pps_adequacy.rds"          = "pps_adequacy",
    stop("Unknown input file, add it to .INPUT_DIR(): ", name)
  )
  if (is.null(owner)) file.path(OutputDir(), "results")
  else file.path(OutputDir(), "results", owner)
}

#Load inputs
.Load <- function(name, required = TRUE) {
  path <- file.path(.INPUT_DIR(name), name)
  if (!file.exists(path)) {
    if (required) {
      stop("Required file not found: ", path,
           "\nRun the corresponding run/*.R script first (see header of this file).")
    }
    cli::cli_alert_warning("Optional file not found, skipping: {path}")
    return(NULL)
  }
  readRDS(path)
}

tree_acc_summary <- .Load("tree_accuracy_summary.rds",  required = TRUE)
conv_df<- .Load("convergence_summary.rds",    required = TRUE)
ka_df<- .Load("known_answer_summary.rds",   required = TRUE)
cgr_df<- .Load("cgr_coverage.rds",            required = FALSE)
pps_df<- .Load("pps_adequacy.rds",             required = FALSE)

cli::cli_h1("Building cross-metric table")
cross_df <- BuildCrossMetricTable(
  tree_acc_summary = tree_acc_summary,
  conv_df= conv_df,
  ka_df= ka_df,
  cgr_df= cgr_df,
  pps_df= pps_df
)
cli::cli_alert_info("Cross-metric table: {nrow(cross_df)} rows (scenario x gridTag x modelID)")

if (is.null(cgr_df)) {
  cli::cli_alert_info("cgr_coverage.rds not found -- run run/validate_cgr.R for a third calibration axis alongside known-answer coverage.")
}
if (is.null(pps_df)) {
  cli::cli_alert_info("pps_adequacy.rds not found -- PPS adequacy generation is currently blocked upstream per your notes; skipped for now.")
}

saveRDS(cross_df, file.path(results_dir, "cross_metric_gridcell.rds"))
utils::write.csv(cross_df, file.path(results_dir, "cross_metric_gridcell.csv"), row.names = FALSE)
cli::cli_alert_success("Saved: cross_metric_gridcell.rds / .csv")

# Model-level scorecard
cli::cli_h1("Model-level scorecard")
scorecard <- ModelLevelScorecard(cross_df)
saveRDS(scorecard, file.path(results_dir, "cross_metric_model_scorecard.rds"))
utils::write.csv(scorecard, file.path(results_dir, "cross_metric_model_scorecard.csv"), row.names = FALSE)
cli::cli_alert_success("Saved: cross_metric_model_scorecard.rds / .csv")

for (scen in unique(scorecard$scenario)) {
  cli::cli_h2("Scenario: {scen} (ranked by tree accuracy, best first)")
  sub <- scorecard[scorecard$scenario == scen, ]
  print_cols <- intersect(c("modelID", "avg_median_cid", "rank_median_cid",
                            "avg_mse_tree_len", "rank_mse_tree_len",
                            "avg_pass_rate", "rank_pass_rate"), colnames(sub))
  print(sub[, print_cols], row.names = FALSE)
}

# Model-level rank correlations (the headline result
cli::cli_h1("Does tree-accuracy rank predict rank on other metrics? (model-level)")
rank_corr <- ModelRankCorrelations(scorecard, B = 1000L)
saveRDS(rank_corr, file.path(results_dir, "cross_metric_rank_correlations.rds"))
utils::write.csv(rank_corr, file.path(results_dir, "cross_metric_rank_correlations.csv"), row.names = FALSE)
cli::cli_alert_success("Saved: cross_metric_rank_correlations.rds / .csv")

for (scen in unique(rank_corr$scenario)) {
  cli::cli_h2("Scenario: {scen}")
  sub <- rank_corr[rank_corr$scenario == scen, ]
  sub <- sub[order(sub$rho), ]
  for (i in seq_len(nrow(sub))) {
    r <- sub[i, ]
    direction <- if (is.na(r$rho)) {
      "not enough data"
    } else if (r$rho > 0.3) {
      "models with better trees tend to rank better here too"
    } else if (r$rho < -0.3) {
      "models with better trees tend to rank WORSE here (worth a closer look)"
    } else {
      "little to no rank relationship"
    }
    cli::cli_alert_info(sprintf(
      "  %-20s rho = %6.2f  [%5.2f, %5.2f]  n=%d  -- %s",
      r$metric, r$rho, r$lower, r$upper, r$n, direction
    ))
  }
}

# Grid-cell-level correlations (within-model, higher-powered)
cli::cli_h1("Within-model grid-cell correlations (CID vs other metrics)")
cell_corr <- GridCellCorrelations(cross_df, B = 1000L)
saveRDS(cell_corr, file.path(results_dir, "cross_metric_gridcell_correlations.rds"))
utils::write.csv(cell_corr, file.path(results_dir, "cross_metric_gridcell_correlations.csv"), row.names = FALSE)
cli::cli_alert_success("Saved: cross_metric_gridcell_correlations.rds / .csv")

cli::cli_alert_info("See cross_metric_gridcell_correlations.csv for the full per-model breakdown.")
strong <- cell_corr[!is.na(cell_corr$rho) & abs(cell_corr$rho) > 0.5, ]
if (nrow(strong) > 0L) {
  cli::cli_h2("Strongest within-model relationships (|rho| > 0.5)")
  print(strong[order(-abs(strong$rho)), c("scenario", "modelID", "metric", "rho", "n")],
        row.names = FALSE)
} else {
  cli::cli_alert_info("No within-model relationship exceeded |rho| = 0.5.")
}

cli::cli_h2("How to read this")
cli::cli_alert_info("Model-level rank correlations answer the supervisor's question directly: do the models with the best trees also win on convergence/calibration? rho near +1 = yes, near -1 = inverted, near 0 = no relationship.")
cli::cli_alert_info("n is small at the model level (<=12) -- treat rho as descriptive, and look at the [lower, upper] bootstrap CI rather than just the point estimate.")
cli::cli_alert_info("Grid-cell correlations are within a single model across parameter regimes -- a different question (\"where THIS model struggles on trees, does it also struggle elsewhere\") with much higher n.")
