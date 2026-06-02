#Fits GAMs and extracts threshold estimates for each models across all parameter axes

# To DO :
# -Load per-replicate CID improvement over Mk baseline.
# - Call ThresholdGAM.R::ThresholdSummary() for each inference model.
# - Run SensitivityCheck() to flag unstable threshold estimates.
#-Export summary data frame and GAM objects for plotting.

source("R/core/_setup.R")

# --- Configuration ---

SCENARIO     <- "nt"
BASELINE_ID  <- "model1"
GAM_K        <- 10L      # Basis dimension for all smooths
RUN_SENSITIVITY <- TRUE  # Re-fit with k*2 and check threshold stability

# Input paths
cid_rep_rds <- file.path(OutputDir(), "results", "tree_accuracy_per_rep.rds")

# Output paths
thresh_rds  <- file.path(OutputDir(), "results", "threshold_summary.rds")
thresh_csv  <- file.path(OutputDir(), "results", "threshold_summary.csv")
gam_rds     <- file.path(OutputDir(), "results", "gam_objects.rds")

dir.create(dirname(thresh_rds), showWarnings = FALSE, recursive = TRUE)

# --- Load data ---
if (!file.exists(cid_rep_rds)) {
  stop("CID per-replicate data not found: ", cid_rep_rds,
       "\nRun analysis/tree_accuracy.R first.")
}

cid_data <- readRDS(cid_rep_rds)
cli::cli_alert_info("Loaded CID data: {nrow(cid_data)} rows.")

# --- Fit GAMs and extract thresholds ---
cli::cli_h1("Fitting threshold GAMs (k = {GAM_K})")

eval_models <- setdiff(MODEL_IDS, BASELINE_ID)
gam_objects <- vector("list", length(eval_models))
names(gam_objects) <- eval_models

threshold_rows <- vector("list", length(eval_models))

predictors <- c("tree_length", "rate_ratio", "chars_per_taxon")

for (mi in seq_along(eval_models)) {
  mid <- eval_models[mi]
  cli::cli_h2("Model: {mid}")

  # Compute improvement for this model
  impr_df <- tryCatch(
    ComputeImprovement(cid_data, mid, BASELINE_ID, SCENARIO),
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

  # Extract thresholds on each parameter axis
  thresholds <- setNames(
    lapply(predictors, function(pred) {
      tryCatch(
        ExtractThreshold(fit, pred, impr_df),
        error = function(e) {
          cli::cli_alert_warning(
            "ExtractThreshold failed for {mid}/{pred}: {conditionMessage(e)}"
          )
          list(threshold = NA_real_, direction = NA_character_,
               pred_range = c(NA_real_, NA_real_))
        }
      )
    }),
    predictors
  )

  # Sensitivity check
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

  # Collect rows
  model_rows <- lapply(predictors, function(pred) {
    thr <- thresholds[[pred]]
    data.frame(
      modelID   = mid,
      predictor = pred,
      threshold = thr$threshold,
      direction = thr$direction,
      range_lo  = thr$pred_range[1],
      range_hi  = thr$pred_range[2],
      stable    = stable_map[[pred]],
      stringsAsFactors = FALSE
    )
  })

  threshold_rows[[mi]] <- do.call(rbind, model_rows)

  cli::cli_alert_info("  tree_length threshold  : {round(thresholds$tree_length$threshold, 3)}")
  cli::cli_alert_info("  rate_ratio threshold   : {round(thresholds$rate_ratio$threshold, 3)}")
  cli::cli_alert_info("  chars_per_taxon thresh : {round(thresholds$chars_per_taxon$threshold, 3)}")
}

# --- Save results ------------------------------------------------------------

thresh_df <- do.call(rbind,
                     threshold_rows[!vapply(threshold_rows, is.null, logical(1))])

if (!is.null(thresh_df) && nrow(thresh_df) > 0L) {
  saveRDS(thresh_df, thresh_rds)
  utils::write.csv(thresh_df, thresh_csv, row.names = FALSE)
  cli::cli_alert_success("Threshold summary saved to:")
  cli::cli_alert_success("  RDS : {thresh_rds}")
  cli::cli_alert_success("  CSV : {thresh_csv}")
} else {
  cli::cli_alert_warning("No threshold results produced.")
}

# Save GAM objects for plotting
gam_objects <- gam_objects[!vapply(gam_objects, is.null, logical(1))]
saveRDS(gam_objects, gam_rds)
cli::cli_alert_success("GAM objects saved to: {gam_rds}")

# --- Unstable threshold report -----------------------------------------------

if (!is.null(thresh_df) && "stable" %in% colnames(thresh_df)) {
  unstable <- thresh_df[!is.na(thresh_df$stable) & !thresh_df$stable, ]
  if (nrow(unstable) > 0L) {
    cli::cli_h2("Unstable thresholds (shift > 10% of predictor range with k*2)")
    print(unstable[, c("modelID", "predictor", "threshold", "stable")])
  } else {
    cli::cli_alert_success("All threshold estimates are stable under k-doubling.")
  }
}
