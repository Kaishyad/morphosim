# Computes Clustering Information Distance (CID) between posterior trees and
# the known true tree for all converged runs under both generative scenarios.

source("R/core/_setup.R")

# --- Configuration ---
SCENARIOS <- c("nt", "mk")

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
converged <- conv_df[conv_df$pass, ]

cli::cli_alert_info(
  "{nrow(converged)} converged run(s) across all scenarios and models."
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

# Join grid parameters for downstream plotting.
# FIX: GridTag() takes a single row, not a full data frame. Was calling
# GridTag(PARAM_GRID) which would silently return only the first row's tag
# recycled across all rows. Now uses apply() to call GridTag() row by row.
grid_lookup         <- PARAM_GRID
grid_lookup$gridTag <- apply(PARAM_GRID, 1, GridTag)
summary_df <- merge(summary_df, grid_lookup, by = "gridTag", all.x = TRUE)

saveRDS(summary_df, cid_rds)
cli::cli_alert_success("Tree accuracy summary saved to: {cid_rds}")

# --- Console report ---

cli::cli_h2("CID summary (NT scenario, model1 vs others)")

nt_m1 <- summary_df[summary_df$scenario == "nt" &
                      summary_df$modelID == "model1", ]
if (nrow(nt_m1) > 0L) {
  cli::cli_alert_info(
    "model1 median CID range: [{round(min(nt_m1$median_cid, na.rm=TRUE), 3)}, ",
    "{round(max(nt_m1$median_cid, na.rm=TRUE), 3)}]"
  )
}

for (mid in MODEL_IDS[-1]) {
  sub <- summary_df[summary_df$scenario == "nt" & summary_df$modelID == mid, ]
  if (nrow(sub) == 0L) next
  cli::cli_alert_info(
    "{mid} median CID range: [{round(min(sub$median_cid, na.rm=TRUE), 3)}, ",
    "{round(max(sub$median_cid, na.rm=TRUE), 3)}]"
  )
}
