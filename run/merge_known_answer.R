# Merges per-model/scenario known_answer_summary_<scenario>_<model>.rds files
# (written by known_answer.R when run one-model-at-a-time in parallel) into the
# single combined results/known_answer_summary.rds / .csv that downstream
# scripts (GAM threshold, correlation analysis, etc.) expect.
#
# Usage:
#   Rscript run/merge_known_answer.R
#   Rscript run/merge_known_answer.R --scenario nt
#
# Run this once after all per-model known_answer jobs for a scenario have
# finished — submitted as a SLURM job with --dependency=afterany:<job1>:...

source("R/core/_setup.R")

args_cli      <- commandArgs(trailingOnly = TRUE)
scenario_flag <- args_cli[which(args_cli == "--scenario") + 1]
SCENARIOS     <- if (!is.na(scenario_flag[1])) scenario_flag else c("nt", "mk")

results_dir <- file.path(OutputDir(), "results")
ka_rds      <- file.path(results_dir, "known_answer_summary.rds")
ka_csv      <- file.path(results_dir, "known_answer_summary.csv")

per_model_files <- list.files(
  results_dir,
  pattern = sprintf("^known_answer_summary_(%s)_model[0-9]+\\.rds$",
                    paste(SCENARIOS, collapse = "|")),
  full.names = TRUE
)

if (length(per_model_files) == 0L) {
  stop("No per-model known_answer_summary_*.rds files found for scenario(s): ",
       paste(SCENARIOS, collapse = ", "))
}

cli::cli_alert_info("Found {length(per_model_files)} per-model file(s) to merge:")
cli::cli_ul(basename(per_model_files))

per_model_dfs <- lapply(per_model_files, readRDS)
new_df <- do.call(rbind, per_model_dfs)

# Merge with any existing combined summary (e.g. previously-merged scenarios),
# de-duplicating on the natural key so re-running the merge is idempotent.
existing_df <- if (file.exists(ka_rds)) readRDS(ka_rds) else NULL

combined_df <- if (!is.null(existing_df)) rbind(existing_df, new_df) else new_df
key <- with(combined_df, paste(scenario, gridTag, modelID, sep = "|"))
combined_df <- combined_df[!duplicated(key, fromLast = TRUE), ]

saveRDS(combined_df, ka_rds)
utils::write.csv(combined_df, ka_csv, row.names = FALSE)

cli::cli_alert_success(
  "Merged known-answer summary: {ka_rds} ({nrow(combined_df)} total rows)"
)

# --- Summary printout
by_model <- aggregate(
  cbind(cov_tree_len, cov_rate_loss) ~ scenario + modelID,
  data    = combined_df,
  FUN     = function(x) round(mean(x, na.rm = TRUE), 3)
)
cli::cli_h2("Mean coverage rates by scenario/model (target ~0.95)")
print(by_model)
