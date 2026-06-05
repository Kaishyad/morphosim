# Fits GAMs and extracts threshold estimates for each model across all
# parameter axes, for both generative scenarios.
#
# For each scenario, CID improvement over the Mk baseline (model1) is computed
# per replicate, a GAM is fitted with three predictors (tree_length, rate_ratio,
# chars_per_taxon), and the parameter threshold at which each model outperforms
# the baseline is extracted. A sensitivity check re-fits with k*2 to flag
# unstable estimates.
#
# Output files are written per scenario to the-matrix/results/:
#   threshold_summary_{scenario}.rds / .csv
#   gam_objects_{scenario}.rds

source("R/core/_setup.R")

# --- Configuration ---

SCENARIOS       <- c("nt", "mk")
BASELINE_ID     <- "model1"
GAM_K           <- 10L    # basis dimension for all smooths
RUN_SENSITIVITY <- TRUE   # re-fit with k*2 and check threshold stability

predictors <- c("tree_length", "rate_ratio", "chars_per_taxon")

# Input
cid_rep_rds <- file.path(OutputDir(), "results", "tree_accuracy_per_rep.rds")

if (!file.exists(cid_rep_rds)) {
  stop("CID per-replicate data not found: ", cid_rep_rds,
       "\nRun run/tree_accuracy.R first.")
}

cid_data <- readRDS(cid_rep_rds)
cli::cli_alert_info("Loaded CID data: {nrow(cid_data)} rows.")

dir.create(file.path(OutputDir(), "results"), showWarnings = FALSE,
           recursive = TRUE)

# --- Main loop over scenarios ------------------------------------------------

for (scenario in SCENARIOS) {
  cli::cli_h1("Scenario: {scenario}")

  # Per-scenario output paths
  thresh_rds <- file.path(OutputDir(), "results",
                          paste0("threshold_summary_", scenario, ".rds"))
  thresh_csv <- file.path(OutputDir(), "results",
                          paste0("threshold_summary_", scenario, ".csv"))
  gam_rds    <- file.path(OutputDir(), "results",
                          paste0("gam_objects_", scenario, ".rds"))

  eval_models    <- setdiff(MODEL_IDS, BASELINE_ID)
  gam_objects    <- vector("list", length(eval_models))
  names(gam_objects) <- eval_models
  threshold_rows <- vector("list", length(eval_models))

  for (mi in seq_along(eval_models)) {
    mid <- eval_models[mi]
    cli::cli_h2("Model: {mid}")

    # Compute per-replicate CID improvement over baseline
    impr_df <- tryCatch(
      ComputeImprovement(cid_data, mid, BASELINE_ID, scenario),
      error = function(e) {
        cli::cli_alert_danger(
          "ComputeImprovement failed for {mid}: {conditionMessage(e)}"
        )
        NULL
      }
    )

    if (is.null(impr_df) || nrow(impr_df) == 0L) {
      cli::cli_alert_warning("No improvement data for {mid}; skipping.")
      next
    }

    # Fit GAM
    fit <- tryCatch(
      FitThresholdGAM(impr_df, k = GAM_K, verbose = FALSE),
      error = function(e) {
        cli::cli_alert_danger(
          "FitThresholdGAM failed for {mid}: {conditionMessage(e)}"
        )
        NULL
      }
    )

    if (is.null(fit)) next
    gam_objects[[mid]] <- fit

    # Extract threshold on each predictor axis
    thresholds <- setNames(
      lapply(predictors, function(pred) {
        tryCatch(
          ExtractThreshold(fit, pred, impr_df),
          error = function(e) {
            cli::cli_alert_warning(
              "ExtractThreshold failed for {mid}/{pred}: {conditionMessage(e)}"
            )
            list(threshold  = NA_real_,
                 direction  = NA_character_,
                 pred_range = c(NA_real_, NA_real_))
          }
        )
      }),
      predictors
    )

    # Sensitivity check: re-fit with k*2 and compare threshold estimates
    stable_map <- if (RUN_SENSITIVITY) {
      sens <- tryCatch(
        SensitivityCheck(impr_df, thresholds, k_orig = GAM_K),
        error = function(e) {
          cli::cli_alert_warning(
            "SensitivityCheck failed for {mid}: {conditionMessage(e)}"
          )
          NULL
        }
      )
      if (!is.null(sens)) {
        setNames(sens$stable, sens$predictor)
      } else {
        setNames(rep(NA, length(predictors)), predictors)
      }
    } else {
      setNames(rep(NA, length(predictors)), predictors)
    }

    # Collect one row per predictor
    threshold_rows[[mi]] <- do.call(rbind, lapply(predictors, function(pred) {
      thr <- thresholds[[pred]]
      data.frame(
        scenario  = scenario,
        modelID   = mid,
        predictor = pred,
        threshold = thr$threshold,
        direction = thr$direction,
        range_lo  = thr$pred_range[1],
        range_hi  = thr$pred_range[2],
        stable    = stable_map[[pred]],
        stringsAsFactors = FALSE
      )
    }))

    cli::cli_alert_info(
      "  tree_length threshold  : {round(thresholds$tree_length$threshold, 3)}"
    )
    cli::cli_alert_info(
      "  rate_ratio threshold   : {round(thresholds$rate_ratio$threshold, 3)}"
    )
    cli::cli_alert_info(
      "  chars_per_taxon thresh : {round(thresholds$chars_per_taxon$threshold, 3)}"
    )
  }

  # --- Save results for this scenario ----------------------------------------

  thresh_df <- do.call(rbind,
                       threshold_rows[!vapply(threshold_rows, is.null,
                                              logical(1))])

  if (!is.null(thresh_df) && nrow(thresh_df) > 0L) {
    saveRDS(thresh_df, thresh_rds)
    utils::write.csv(thresh_df, thresh_csv, row.names = FALSE)
    cli::cli_alert_success("Threshold summary saved to:")
    cli::cli_alert_success("  RDS : {thresh_rds}")
    cli::cli_alert_success("  CSV : {thresh_csv}")
  } else {
    cli::cli_alert_warning("No threshold results produced for {scenario}.")
  }

  gam_objects <- gam_objects[!vapply(gam_objects, is.null, logical(1))]
  saveRDS(gam_objects, gam_rds)
  cli::cli_alert_success("GAM objects saved to: {gam_rds}")

  # --- Unstable threshold report ---------------------------------------------

  if (!is.null(thresh_df) && "stable" %in% colnames(thresh_df)) {
    unstable <- thresh_df[!is.na(thresh_df$stable) & !thresh_df$stable, ]
    if (nrow(unstable) > 0L) {
      cli::cli_h2("Unstable thresholds (shift > 10% of predictor range with k*2)")
      print(unstable[, c("scenario", "modelID", "predictor", "threshold",
                         "stable")])
    } else {
      cli::cli_alert_success(
        "All threshold estimates stable under k-doubling ({scenario})."
      )
    }
  }
}
