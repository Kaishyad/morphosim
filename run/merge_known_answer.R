# Merges per-model/scenario known_answer_summary_<scenario>_<model>.rds files
#
#Rscript run/merge_known_answer.R
#Rscript run/merge_known_answer.R --scenario nt

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
cli::cli_h2("Mean coverage rates by scenario/model (target ~0.95)")

by_model <- do.call(rbind, lapply(split(combined_df, list(combined_df$scenario, combined_df$modelID)), function(x) {
  data.frame(
    scenario      = x$scenario[1],
    modelID       = x$modelID[1],
    cov_tree_len  = round(mean(x$cov_tree_len,  na.rm = TRUE), 3),
    cov_rate_loss = round(mean(x$cov_rate_loss, na.rm = TRUE), 3)
  )
}))
by_model <- by_model[order(by_model$scenario, by_model$modelID), ]
print(by_model, row.names = FALSE)
