#Merges per-model/scenario convergence_summary_<scenario>_<model>.rds files
#when run one-model-at-a-time in parallel)

source("R/core/_setup.R")

args_cli      <- commandArgs(trailingOnly = TRUE)
scenario_flag <- args_cli[which(args_cli == "--scenario") + 1]
SCENARIOS     <- if (!is.na(scenario_flag[1])) scenario_flag else c("nt", "mk")

results_dir <- file.path(OutputDir(), "results")
conv_rds    <- file.path(results_dir, "convergence_summary.rds")
requeue_f   <- file.path(results_dir, "requeue_list.txt")

per_model_files <- list.files(
  results_dir,
  pattern = sprintf("^convergence_summary_(%s)_model[0-9]+\\.rds$",
                     paste(SCENARIOS, collapse = "|")),
  full.names = TRUE
)

if (length(per_model_files) == 0L) {
  stop("No per-model convergence_summary_*.rds files found for scenario(s): ",
       paste(SCENARIOS, collapse = ", "))
}

cli::cli_alert_info("Found {length(per_model_files)} per-model file(s) to merge:")
cli::cli_ul(basename(per_model_files))

per_model_dfs <- lapply(per_model_files, readRDS)
new_df <- do.call(rbind, per_model_dfs)

# Merge with any existing combined summary (e.g. previously-merged scenarios),
# de-duplicating on the natural key so re-running the merge is idempotent.
existing_df <- if (file.exists(conv_rds)) readRDS(conv_rds) else NULL

combined_df <- if (!is.null(existing_df)) rbind(existing_df, new_df) else new_df
key <- with(combined_df, paste(scenario, gridTag, repID, modelID, sep = "|"))
combined_df <- combined_df[!duplicated(key, fromLast = TRUE), ]

saveRDS(combined_df, conv_rds)
cli::cli_alert_success("Merged combined summary saved to: {conv_rds} ({nrow(combined_df)} total rows)")

# --- Rebuild requeue list from the merged, de-duplicated dataset
failed_runs <- combined_df[!combined_df$pass, ]

if (nrow(failed_runs) == 0L) {
  cli::cli_alert_success("All runs passed — no re-queuing needed.")
  writeLines("# All runs converged; no re-submissions needed.", requeue_f)
} else {
  requeue_lines <- apply(failed_runs, 1, function(r) {
    paste(r["scenario"], r["gridTag"], r["repID"], r["modelID"], sep = "\t")
  })

  writeLines(
    c("# Failed runs for re-submission via submit_inference.R",
      "# Columns: scenario\tgridTag\trepID\tmodelID",
      requeue_lines),
    requeue_f
  )

  cli::cli_alert_warning("{nrow(failed_runs)} failed run(s) written to: {requeue_f}")
}

# --- Summary printout
n_pass <- sum(combined_df$pass, na.rm = TRUE)
n_fail <- sum(!combined_df$pass, na.rm = TRUE)
n_tot  <- nrow(combined_df)

cli::cli_h2("Merged convergence summary")
cli::cli_alert_info("Total runs checked : {n_tot}")
cli::cli_alert_info("Passed             : {n_pass} ({round(100 * n_pass / n_tot, 1)}%)")
cli::cli_alert_info("Failed             : {n_fail} ({round(100 * n_fail / n_tot, 1)}%)")

by_model <- aggregate(pass ~ scenario + modelID, data = combined_df, FUN = mean)
by_model$pass <- round(by_model$pass * 100, 1)
print(by_model)
