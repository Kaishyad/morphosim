## ============================================================
## run_all.R
## Runs the full visualization suite end to end.
## Run from the morphosim repo root:  Rscript viz/run_all.R
## Figures are written to <the-matrix>/figures/ (see 00_config_theme.R).
## ============================================================

if (!file.exists("R/core/_setup.R")) {
  stop("Run this from the morphosim repo root, e.g.: Rscript viz/run_all.R")
}

scripts <- c(
  "viz/01_tree_accuracy_plots.R",
  "viz/02_convergence_diagnostics.R",
  "viz/03_parameter_grid_effects.R",
  # "viz/04_imputation_accuracy_plots.R",  # skipped for now -- ignoring imputation
  "viz/05_summary_dashboard.R"
)

for (s in scripts) {
  message("\n=========================================")
  message("Running: ", s)
  message("=========================================")
  tryCatch(
    source(s, echo = FALSE),
    error = function(e) message("  !! Failed: ", conditionMessage(e))
  )
}

message("\nAll done. Check the-matrix/figures/ for output.")
