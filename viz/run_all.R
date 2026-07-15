# Runs the full visualization suite end to end.

if (!file.exists("R/core/_setup.R")) {
  stop("Run this from the morphosim repo root, e.g.: Rscript viz/run_all.R")
}

scripts <- c(
  "viz/01_tree_accuracy_plots.R",
  "viz/02_convergence_diagnostics.R",
  "viz/03_parameter_grid_effects.R",
# "viz/04_imputation_accuracy_plots.R",  # skipped for now -- ignoring imputation
  "viz/05_summary_dashboard.R",
  "viz/06_parameter_grid_by_model.R",
  "viz/07_cross_metric_analysis.R",  # requires run/cross_metric_analysis.R to have been run first
  "viz/08_tree_similarity_grid.R",
  "viz/09_model_deep_dive.R"        # all-model ranking, param main effects, mk vs nt, readable tables
)

for (s in scripts) {
  message("Running: ", s)
  tryCatch(
    source(s, echo = FALSE),
    error = function(e) message("  !! Failed: ", conditionMessage(e))
  )
}

message("\nAll done. Check the-matrix/figures/ for output.")
