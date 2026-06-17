# Computes Clustering Information Distance (CID) between posterior trees and
# the known true tree for all converged runs under both generative scenarios.

source("R/core/_setup.R")

# --- Argument parsing ---
args_cli      <- commandArgs(trailingOnly = TRUE)
scenario_flag <- args_cli[which(args_cli == "--scenario") + 1]
model_flag    <- args_cli[which(args_cli == "--model")    + 1]

SCENARIOS  <- if (!is.na(scenario_flag[1])) scenario_flag else c("nt", "mk")
MODEL_IDS  <- if (!is.na(model_flag[1]))    model_flag    else MODEL_IDS

message(sprintf("Scenarios: %s | Models: %s",
                paste(SCENARIOS,  collapse = ", "),
                paste(MODEL_IDS,  collapse = ", ")))

# Output paths
cid_rds     <- file.path(OutputDir(), "results", "tree_accuracy_summary.rds")
cid_rep_rds <- file.path(OutputDir(), "results", "tree_accuracy_per_rep.rds")

dir.create(dirname(cid_rds), showWarnings = FALSE, recursive = TRUE)

# --- Load convergence filter ---
conv_rds <- file.path(OutputDir(), "results", "convergence_summary.rds")

if (!file.exists(conv_rds)) {
  stop("Convergence summary not found: ", conv_rds,
       "\nRun run/check_convergence.R first.")
}

conv_df   <- readRDS(conv_rds)
converged <- conv_df[conv_df$pass & conv_df$scenario %in% SCENARIOS &
                       conv_df$modelID %in% MODEL_IDS, ]

cli::cli_alert_info(
  "{nrow(converged)} converged run(s) across selected scenarios and models."
)

# --- Per-replicate CID ---

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
    gridTag    = row$gridTag,
    repID      = row$repID,
    modelID    = row$modelID,
    median_cid = if (!is.null(cid_vec)) median(cid_vec, na.rm = TRUE) else NA_real_,
    iqr_cid    = if (!is.null(cid_vec)) IQR(cid_vec,    na.rm = TRUE) else NA_real_,
    n_trees    = if (!is.null(cid_vec)) sum(!is.na(cid_vec))          else 0L,
    stringsAsFactors = FALSE
  )

  if (ri %% 100L == 0L) {
    cli::cli_alert_info("  {ri}/{nrow(converged)} replicates processed...")
  }
}

per_rep_df <- do.call(rbind, per_rep_rows)
saveRDS(per_rep_df, cid_rep_rds)
cli::cli_alert_success("Per-replicate CID saved to: {cid_rep_rds}")

# --- Grid-cell summary (median of medians) ---

cli::cli_h1("Summarising by grid cell")

summary_rows <- vector("list", 0L)

for (scenario in SCENARIOS) {
  grid        <- ScenarioGrid(scenario)  # FIX: use scenario-specific grid
  grid$gridTag <- apply(grid, 1, function(i) GridTag(as.list(i)))
  

  for (mid in MODEL_IDS) {
    sub <- per_rep_df[per_rep_df$scenario == scenario &
                        per_rep_df$modelID == mid, ]
    if (nrow(sub) == 0L) next

    for (gt in unique(sub$gridTag)) {
      cell <- sub[sub$gridTag == gt, ]
      summary_rows[[length(summary_rows) + 1L]] <- data.frame(
        scenario   = scenario,
        gridTag    = gt,
        modelID    = mid,
        median_cid = median(cell$median_cid, na.rm = TRUE),
        iqr_cid    = IQR(cell$median_cid,    na.rm = TRUE),
        n_reps     = sum(!is.na(cell$median_cid)),
        stringsAsFactors = FALSE
      )
    }
  }
}

summary_df <- do.call(rbind, summary_rows)

# Join grid parameters for downstream plotting
summary_df <- merge(summary_df, grid, by = "gridTag", all.x = TRUE)

saveRDS(summary_df, cid_rds)
cli::cli_alert_success("Tree accuracy summary saved to: {cid_rds}")

# --- Console report ---

cli::cli_h2("CID summary (mk scenario, model1)")

mk_m1 <- summary_df[summary_df$scenario == "mk" &
                      summary_df$modelID == "model1", ]
if (nrow(mk_m1) > 0L) {
  cli::cli_alert_info(
    "model1 median CID range: [{round(min(mk_m1$median_cid, na.rm=TRUE), 3)}, ",
    "{round(max(mk_m1$median_cid, na.rm=TRUE), 3)}]"
  )
}
