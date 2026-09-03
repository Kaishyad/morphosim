#does clustering information distance (cid) between posterior trees and the known true tree for all converged runs under both generative scenarios

source("R/core/_setup.R")

args_cli  <- commandArgs(trailingOnly = TRUE)
scenario_flag <- args_cli[which(args_cli == "--scenario") + 1]
model_flag    <- args_cli[which(args_cli == "--model")    + 1]

SCENARIOS <- if (!is.na(scenario_flag[1])) scenario_flag else c("nt", "mk")
MODEL_IDS <- if (!is.na(model_flag[1]))    model_flag    else MODEL_IDS

message(sprintf("Scenarios: %s | Models: %s",
                paste(SCENARIOS,  collapse = ", "),
                paste(MODEL_IDS,  collapse = ", ")))

#model outpt paths
SINGLE_MODEL_MODE <- !is.na(model_flag[1])

results_dir <- file.path(OutputDir(), "results", "tree_accuracy")
dir.create(results_dir, showWarnings = FALSE, recursive = TRUE)

.RepFile <- function(scenario) {
  if (SINGLE_MODEL_MODE) {
    file.path(results_dir,
              sprintf("tree_accuracy_per_rep_%s_%s.rds", scenario, MODEL_IDS[1]))
  } else {
    file.path(results_dir, "tree_accuracy_per_rep.rds")
  }
}

cid_rds  <- file.path(results_dir, "tree_accuracy_summary.rds")
cid_rep_rds <- file.path(results_dir, "tree_accuracy_per_rep.rds")

#convergence 
conv_rds <- file.path(OutputDir(), "results", "convergence_summary.rds")

if (!file.exists(conv_rds)) {
  stop("Convergence summary not found: ", conv_rds,
       "\nRun run/check_convergence.R first.")
}

conv_df  <- readRDS(conv_rds)
converged <- conv_df[conv_df$pass & conv_df$scenario %in% SCENARIOS &
                       conv_df$modelID %in% MODEL_IDS, ]

cli::cli_alert_info(
  "{nrow(converged)} converged run(s) across selected scenarios and models."
)

#per-replicate cid
per_rep_rows <- vector("list", nrow(converged))

cli::cli_h1("Computing per-replicate CID")

for (ri in seq_len(nrow(converged))) {
  row     <- converged[ri, ]
  cid_vec <- tryCatch(
    TreeAccuracy(row$scenario, row$gridTag, row$repID, row$modelID),
    error = function(e) {
      warning("TreeAccuracy failed for ",
              paste(row$scenario, row$gridTag, row$repID, row$modelID,
                    sep = "/"),
              ": ", conditionMessage(e))
      NULL
    }
  )

  per_rep_rows[[ri]] <- data.frame(
    scenario   = row$scenario,
    gridTag   = row$gridTag,
    repID    = row$repID,
    modelID    = row$modelID,
    median_cid = if (!is.null(cid_vec)) median(cid_vec, na.rm = TRUE) else NA_real_,
    iqr_cid    = if (!is.null(cid_vec)) IQR(cid_vec,    na.rm = TRUE) else NA_real_,
    n_trees    = if (!is.null(cid_vec)) sum(!is.na(cid_vec))  else 0L,
    stringsAsFactors = FALSE
  )

  if (ri %% 100L == 0L) {
    cli::cli_alert_info("  {ri}/{nrow(converged)} replicates processed...")
    # save progress so a walltime kill doesn't lose everything
    partial <- do.call(rbind, per_rep_rows[seq_len(ri)])
    saveRDS(partial, .RepFile(SCENARIOS[1]))
  }
}

per_rep_df <- do.call(rbind, per_rep_rows)

if (SINGLE_MODEL_MODE) {
  saveRDS(per_rep_df, .RepFile(SCENARIOS[1]))
  cli::cli_alert_success("Per-model per-rep CID saved to: {(.RepFile(SCENARIOS[1]))}")
  cli::cli_alert_info("Run merge_tree_accuracy.R after all model jobs finish.")
  quit(save = "no", status = 0)
} else {
  saveRDS(per_rep_df, cid_rep_rds)
  cli::cli_alert_success("Per-replicate CID saved to: {cid_rep_rds}")
}

#grid-cell summary median of medians
cli::cli_h1("Summarising by grid cell")

summary_rows <- vector("list", 0L)

for (scenario in SCENARIOS) {
  scenario_grid         <- ScenarioGrid(scenario)
  scenario_grid$gridTag <- vapply(seq_len(nrow(scenario_grid)),function(i) GridTag(as.list(scenario_grid[i, ])), character(1))

  for (mid in MODEL_IDS) {
    sub <- per_rep_df[per_rep_df$scenario == scenario &
                        per_rep_df$modelID == mid, ]
    if (nrow(sub) == 0L) next

    for (gt in unique(sub$gridTag)) {
      cell <- sub[sub$gridTag == gt, ]
      summary_rows[[length(summary_rows) + 1L]] <- data.frame(
        scenario   = scenario,
        gridTag   = gt,
        modelID  = mid,
        median_cid = median(cell$median_cid, na.rm = TRUE),
        iqr_cid = IQR(cell$median_cid,    na.rm = TRUE),
        n_reps = sum(!is.na(cell$median_cid)),
        stringsAsFactors = FALSE
      )
    }
  }
}

summary_df <- do.call(rbind, summary_rows)

#join grid parameters per-scenario to avoid cross-contamination when both scenarios are processed in the same run; merge separately then combine
summary_df <- do.call(rbind, lapply(SCENARIOS, function(sc) {
  sc_grid<- ScenarioGrid(sc)
  sc_grid$gridTag <- vapply(seq_len(nrow(sc_grid)),
                             function(i) GridTag(as.list(sc_grid[i, ])),
                             character(1))
  sub <- summary_df[summary_df$scenario == sc, ]
  merge(sub, sc_grid, by = "gridTag", all.x = TRUE)
}))

saveRDS(summary_df, cid_rds)
cli::cli_alert_success("Tree accuracy summary saved to: {cid_rds}")

#report
cli::cli_h2("CID summary (mk scenario, model1)")

mk_m1 <- summary_df[summary_df$scenario == "mk" &
                      summary_df$modelID == "model1", ]
if (nrow(mk_m1) > 0L) {
  cli::cli_alert_info(
    "model1 median CID range: [{round(min(mk_m1$median_cid, na.rm=TRUE), 3)}, ",
    "{round(max(mk_m1$median_cid, na.rm=TRUE), 3)}]"
  )
}
