#applies imputation accuracy scoring across the full
#parameter grid and inference models, then performs pairwise Wilcoxon
#signed-rank tests versus the Mk baseline (Model 1).

source("R/core/_setup.R")
# FIX: R/validation/ is not in _setup.R's auto-source loop, so
# ScoreImputation()/WilcoxonImputation() below would be undefined without
# this. Same issue caught and fixed here as before imputation was removed.
source("R/validation/Imputation.R")

# --- Configuration ---

SCENARIOS    <- c("nt", "mk")
PARTITIONS   <- c("neo", "trans")

# Output paths
acc_rds      <- file.path(OutputDir(), "results", "imputation_accuracy.rds")
acc_rep_rds  <- file.path(OutputDir(), "results", "imputation_accuracy_per_rep.rds")
wilcox_rds   <- file.path(OutputDir(), "results", "imputation_wilcoxon.rds")

dir.create(dirname(acc_rds), showWarnings = FALSE, recursive = TRUE)

# --- Load convergence filter ---

conv_rds <- file.path(OutputDir(), "results", "convergence_summary.rds")
if (!file.exists(conv_rds)) {
  stop("Convergence summary not found: ", conv_rds,
       "\nRun run/convergence/check_convergence.R first.")
}

conv_df   <- readRDS(conv_rds)
converged <- conv_df[conv_df$pass, ]
cli::cli_alert_info("{nrow(converged)} converged run(s) for imputation analysis.")

# --- Per-replicate accuracy ---

cli::cli_h1("Scoring imputation accuracy per replicate")

per_rep_rows <- vector("list", nrow(converged))

for (ri in seq_len(nrow(converged))) {
  row <- converged[ri, ]

  acc_neo   <- tryCatch(
    ScoreImputation(row$scenario, row$gridTag, row$repID, row$modelID, "neo"),
    error = function(e) { warning(conditionMessage(e)); NA_real_ }
  )
  acc_trans <- tryCatch(
    ScoreImputation(row$scenario, row$gridTag, row$repID, row$modelID, "trans"),
    error = function(e) { warning(conditionMessage(e)); NA_real_ }
  )

  per_rep_rows[[ri]] <- data.frame(
    scenario   = row$scenario,
    gridTag    = row$gridTag,
    repID      = row$repID,
    modelID    = row$modelID,
    acc_neo    = acc_neo,
    acc_trans  = acc_trans,
    mean_acc   = mean(c(acc_neo, acc_trans), na.rm = TRUE),
    stringsAsFactors = FALSE
  )

  if (ri %% 100L == 0L) {
    cli::cli_alert_info("  {ri}/{nrow(converged)} scored...")
  }
}

per_rep_df <- do.call(rbind, per_rep_rows)
saveRDS(per_rep_df, acc_rep_rds)
cli::cli_alert_success("Per-replicate imputation accuracy saved to: {acc_rep_rds}")

# --- Grid-cell summary ---

cli::cli_h1("Summarising imputation accuracy by grid cell")

summary_rows <- vector("list", 0L)

for (scenario in SCENARIOS) {
  for (mid in MODEL_IDS) {
    sub <- per_rep_df[per_rep_df$scenario == scenario &
                        per_rep_df$modelID  == mid, ]
    if (nrow(sub) == 0L) next

    for (gt in unique(sub$gridTag)) {
      cell <- sub[sub$gridTag == gt, ]

      summary_rows[[length(summary_rows) + 1L]] <- data.frame(
        scenario         = scenario,
        gridTag          = gt,
        modelID          = mid,
        median_acc       = median(cell$mean_acc,  na.rm = TRUE),
        iqr_acc          = IQR(cell$mean_acc,     na.rm = TRUE),
        median_acc_neo   = median(cell$acc_neo,   na.rm = TRUE),
        median_acc_trans = median(cell$acc_trans, na.rm = TRUE),
        n_reps           = sum(!is.na(cell$mean_acc)),
        stringsAsFactors = FALSE
      )
    }
  }
}

summary_df <- do.call(rbind, summary_rows)

# Join grid parameters
grid_lookup          <- PARAM_GRID
grid_lookup$gridTag  <- GridTag(PARAM_GRID)
summary_df <- merge(summary_df, grid_lookup, by = "gridTag", all.x = TRUE)

saveRDS(summary_df, acc_rds)
cli::cli_alert_success("Imputation accuracy summary saved to: {acc_rds}")

# --- Pairwise Wilcoxon tests vs Mk baseline ---

cli::cli_h1("Pairwise Wilcoxon signed-rank tests vs scenario baseline")

wilcox_rows    <- vector("list", 0L)

for (scenario in SCENARIOS) {
  # FIX: use the scenario-specific baseline (same BASELINE_BY_SCENARIO fix
  # already applied in run/gam_threshold/gam_threshold.R) -- nt's correctly
  # specified model is model8, not model1.
  baseline_id    <- BASELINE_BY_SCENARIO[[scenario]]
  compare_models <- setdiff(MODEL_IDS, baseline_id)

  for (gt in unique(per_rep_df$gridTag)) {
    for (mid in compare_models) {
      res <- tryCatch(
        WilcoxonImputation(scenario, gt, mid,
                           baselineID = baseline_id,
                           nRep       = N_REP),
        error = function(e) {
          warning("WilcoxonImputation failed for ", mid, " ", gt, ": ",
                  conditionMessage(e))
          list(statistic = NA, p.value = NA, direction = NA)
        }
      )

      wilcox_rows[[length(wilcox_rows) + 1L]] <- data.frame(
        scenario   = scenario,
        gridTag    = gt,
        modelID    = mid,
        baselineID = baseline_id,
        statistic  = res$statistic,
        p.value    = res$p.value,
        direction  = res$direction,
        stringsAsFactors = FALSE
      )
    }
  }
}

wilcox_df <- do.call(rbind, wilcox_rows)

# Benjamini-Hochberg correction within each (scenario, gridTag)
wilcox_df$p.adj <- stats::p.adjust(wilcox_df$p.value, method = "BH")

saveRDS(wilcox_df, wilcox_rds)
cli::cli_alert_success("Wilcoxon results saved to: {wilcox_rds}")

# --- Console report ---

cli::cli_h2("Models significantly better than Mk baseline (BH-adjusted p < 0.05)")

sig_better <- wilcox_df[!is.na(wilcox_df$p.adj) &
                           wilcox_df$p.adj < 0.05 &
                           !is.na(wilcox_df$direction) &
                           wilcox_df$direction == "better", ]
cli::cli_alert_info("{nrow(sig_better)} (scenario × model × grid) combinations significantly better")

sig_worse <- wilcox_df[!is.na(wilcox_df$p.adj) &
                          wilcox_df$p.adj < 0.05 &
                          !is.na(wilcox_df$direction) &
                          wilcox_df$direction == "worse", ]
cli::cli_alert_info("{nrow(sig_worse)} (scenario × model × grid) combinations significantly worse")
