#Computes Spearman's rank correlation between imputation accuracy and
#topological accuracy (CID) across the model space, with bootstrap CIs.

#TO DO:
# -Load per-replicate CID summaries (from tree_accuracy.R output).
# - Load per-replicate imputation accuracy (from imputation_analysis.R output).
# - Call Correlation.R::CorrelationSummary() for each model.
# -Export tidy data frame as .rds and CSV for dissertation Table 6.3.

source("R/core/_setup.R")

# --- Configuration ---
SCENARIO      <- "nt"
BOOTSTRAP_B   <- 1000L

# Input paths
cid_rep_rds  <- file.path(OutputDir(), "results", "tree_accuracy_per_rep.rds")
acc_rep_rds  <- file.path(OutputDir(), "results", "imputation_accuracy_per_rep.rds")

# Output paths
corr_rds     <- file.path(OutputDir(), "results", "correlation_summary.rds")
corr_csv     <- file.path(OutputDir(), "results", "correlation_summary.csv")

dir.create(dirname(corr_rds), showWarnings = FALSE, recursive = TRUE)

# --- Load data ---

if (!file.exists(cid_rep_rds)) {
  stop("CID per-replicate data not found: ", cid_rep_rds,
       "\nRun analysis/tree_accuracy.R first.")
}
if (!file.exists(acc_rep_rds)) {
  stop("Imputation accuracy per-replicate data not found: ", acc_rep_rds,
       "\nRun analysis/imputation_analysis.R first.")
}

cid_data <- readRDS(cid_rep_rds)
acc_data <- readRDS(acc_rep_rds)

cli::cli_alert_info(
  "Loaded CID data: {nrow(cid_data)} rows; imputation data: {nrow(acc_data)} rows."
)

# --- Compute correlations ---

cli::cli_h1("Computing Spearman correlations (B = {BOOTSTRAP_B} bootstrap resamples)")

corr_df <- tryCatch(
  CorrelationSummary(
    cid_data  = cid_data,
    acc_data  = acc_data,
    scenario  = SCENARIO,
    model_ids = MODEL_IDS,
    B         = BOOTSTRAP_B
  ),
  error = function(e) {
    stop("CorrelationSummary failed: ", conditionMessage(e))
  }
)

if (is.null(corr_df) || nrow(corr_df) == 0L) {
  stop("No correlation results produced. Check input data.")
}

# --- Join grid parameters ---

grid_lookup         <- PARAM_GRID
grid_lookup$gridTag <- GridTag(PARAM_GRID)
corr_df <- merge(corr_df, grid_lookup, by = "gridTag", all.x = TRUE)

# --- Save results ---

saveRDS(corr_df, corr_rds)
utils::write.csv(corr_df, corr_csv, row.names = FALSE)

cli::cli_alert_success("Correlation summary saved to:")
cli::cli_alert_success("  RDS : {corr_rds}")
cli::cli_alert_success("  CSV : {corr_csv}")

# --- Console report ---

cli::cli_h2("Correlation summary (Table 6.3 preview)")

for (mid in MODEL_IDS) {
  sub <- corr_df[corr_df$modelID == mid, ]
  if (nrow(sub) == 0L) next

  n_sig     <- sum(sub$sig,       na.rm = TRUE)
  n_neg_sig <- sum(sub$sig & sub$direction == "negative", na.rm = TRUE)
  med_rho   <- round(median(sub$rho, na.rm = TRUE), 3)

  cli::cli_alert_info(
    "{mid}: median rho = {med_rho}, {n_sig}/{nrow(sub)} cells significant, ",
    "{n_neg_sig} negative (better imputation <-> better topology)"
  )
}
