# Runs the full visualization suite end to end.

if (!file.exists("R/core/_setup.R")) {
  stop("Run this from the morphosim repo root, e.g.: Rscript run/shared/run_all.R")
}

scripts <- c(
  "run/tree_accuracy/tree_accuracy_plots.R",
  "run/convergence/convergence_diagnostics.R",
  "run/gam_threshold/parameter_grid_effects.R",
  "run/shared/summary_dashboard.R",
  "run/tree_accuracy/parameter_grid_by_model.R",
  "run/cross_metric/cross_metric_plots.R",  
  "run/tree_accuracy/tree_similarity_grid.R",
  "run/model_comparison/model_deep_dive.R",        
  "run/known_answer/known_answer_analysis.R"
)

for (s in scripts) {
  message("Running: ", s)
  tryCatch(
    source(s, echo = FALSE),
    error = function(e) message("  !! Failed: ", conditionMessage(e))
  )
}

message("\nAll done. Check the-matrix/figures/ for output.")
