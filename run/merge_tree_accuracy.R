# Merges per-model/scenario tree_accuracy_per_rep_<scenario>_<model>.rds files

#Rscript run/merge_tree_accuracy.R
#Rscript run/merge_tree_accuracy.R --scenario nt
#
# Run once after all per-model tree_accuracy jobs finish.

source("R/core/_setup.R")

args_cli      <- commandArgs(trailingOnly = TRUE)
scenario_flag <- args_cli[which(args_cli == "--scenario") + 1]
SCENARIOS     <- if (!is.na(scenario_flag[1])) scenario_flag else c("nt", "mk")

results_dir <- file.path(OutputDir(), "results")
rep_rds     <- file.path(results_dir, "tree_accuracy_per_rep.rds")
sum_rds     <- file.path(results_dir, "tree_accuracy_summary.rds")

# --- Merge per-rep files
per_model_files <- list.files(
  results_dir,
  pattern = sprintf("^tree_accuracy_per_rep_(%s)_model[0-9]+\\.rds$",
                    paste(SCENARIOS, collapse = "|")),
  full.names = TRUE
)

if (length(per_model_files) == 0L) {
  stop("No per-model tree_accuracy_per_rep_*.rds files found for scenario(s): ",
       paste(SCENARIOS, collapse = ", "))
}

cli::cli_alert_info("Found {length(per_model_files)} per-model file(s) to merge:")
cli::cli_ul(basename(per_model_files))

new_rep_df <- do.call(rbind, lapply(per_model_files, readRDS))


existing_rep <- if (file.exists(rep_rds)) readRDS(rep_rds) else NULL
combined_rep <- if (!is.null(existing_rep)) rbind(existing_rep, new_rep_df) else new_rep_df
key <- with(combined_rep, paste(scenario, gridTag, repID, modelID, sep = "|"))
combined_rep <- combined_rep[!duplicated(key, fromLast = TRUE), ]

saveRDS(combined_rep, rep_rds)
cli::cli_alert_success(
  "Merged per-rep CID saved: {rep_rds} ({nrow(combined_rep)} rows)"
)

# --- Rebuild grid-cell summary from the full combined per-rep data
cli::cli_h1("Rebuilding grid-cell summary")

all_scenarios <- unique(combined_rep$scenario)
scenario_summaries <- lapply(all_scenarios, function(sc) {
  sc_grid         <- ScenarioGrid(sc)
  sc_grid$gridTag <- vapply(seq_len(nrow(sc_grid)),
                             function(i) GridTag(as.list(sc_grid[i, ])),
                             character(1))

  sc_rep <- combined_rep[combined_rep$scenario == sc, ]
  rows   <- vector("list", 0L)

  for (mid in unique(sc_rep$modelID)) {
    sub <- sc_rep[sc_rep$modelID == mid, ]
    for (gt in unique(sub$gridTag)) {
      cell <- sub[sub$gridTag == gt, ]
      rows[[length(rows) + 1L]] <- data.frame(
        scenario   = sc,
        gridTag    = gt,
        modelID    = mid,
        median_cid = median(cell$median_cid, na.rm = TRUE),
        iqr_cid    = IQR(cell$median_cid,    na.rm = TRUE),
        n_reps     = sum(!is.na(cell$median_cid)),
        stringsAsFactors = FALSE
      )
    }
  }

  sc_summary <- do.call(rbind, rows)
  merge(sc_summary, sc_grid, by = "gridTag", all.x = TRUE)
})


all_cols <- unique(unlist(lapply(scenario_summaries, names)))
scenario_summaries <- lapply(scenario_summaries, function(df) {
  missing <- setdiff(all_cols, names(df))
  if (length(missing) > 0L) {
    df[missing] <- NA
  }
  df[all_cols]
})

summary_df <- do.call(rbind, scenario_summaries)

saveRDS(summary_df, sum_rds)
cli::cli_alert_success(
  "Grid-cell summary saved: {sum_rds} ({nrow(summary_df)} rows)"
)

# --- Console summary
cli::cli_h2("Median CID by scenario/model")
by_model <- do.call(rbind, lapply(
  split(summary_df, list(summary_df$scenario, summary_df$modelID)),
  function(x) data.frame(
    scenario   = x$scenario[1],
    modelID    = x$modelID[1],
    median_cid = round(median(x$median_cid, na.rm = TRUE), 4)
  )
))
by_model <- by_model[order(by_model$scenario, by_model$modelID), ]
print(by_model, row.names = FALSE)
