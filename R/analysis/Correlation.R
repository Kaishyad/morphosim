# Tests whether imputation accuracy is a reliable proxy for topological accuracy across the model space

#SpearmanCorrelation() Computes Spearman's rho between per-replicate median
#                       CID and mean imputation accuracy; returns rho and bootstrap 95% CI via the boot package.
#CorrelationTest() - Applies SpearmanCorrelation() for each (model, grid cell) combination and collects results.
#CorrelationSummary()  - Produces a tidy data frame of rho, lower CI, upper CI, and p-value across all models


#' Compute Spearman's rho between per-replicate CID and imputation accuracy
#'
#' For a single (model, grid-cell) combination, correlates the median CID
#' (lower = better tree accuracy) against mean imputation accuracy (higher =
#' better). Note the sign convention: rho < 0 means better imputation
#' predicts better topology.
#'
#' Bootstrap 95% CI uses the percentile method with B = 1000 resamples
#' (pairs of observations resampled jointly).
#'
#' @param cid_vec    Numeric vector of per-replicate median CID values.
#' @param acc_vec    Numeric vector of per-replicate mean imputation accuracy.
#' @param B          Number of bootstrap resamples (default 1000).
#' @param conf       Confidence level for CI (default 0.95).
#' @return Named list:
#'   \item{rho}{Observed Spearman's rho.}
#'   \item{lower}{Lower bootstrap CI bound.}
#'   \item{upper}{Upper bootstrap CI bound.}
#'   \item{p.value}{Two-sided p-value from cor.test().}
#'   \item{n}{Number of complete pairs used.}
#' @importFrom stats cor.test
#' @export
SpearmanCorrelation <- function(cid_vec, acc_vec, B = 1000L, conf = 0.95) {
  # Drop pairs where either is NA
  keep     <- !is.na(cid_vec) & !is.na(acc_vec)
  cid_vec  <- cid_vec[keep]
  acc_vec  <- acc_vec[keep]
  n        <- length(cid_vec)

  if (n < 5L) {
    warning("Fewer than 5 complete pairs; returning NA")
    return(list(rho = NA_real_, lower = NA_real_,
                upper = NA_real_, p.value = NA_real_, n = n))
  }

  # Observed correlation and p-value
  ct    <- cor.test(cid_vec, acc_vec, method = "spearman", exact = FALSE)
  rho   <- unname(ct$estimate)
  pval  <- ct$p.value

  # Bootstrap CI — resample paired observations
  set.seed(42L)
  rho_boot <- vapply(seq_len(B), function(i) {
    idx <- sample.int(n, n, replace = TRUE)
    suppressWarnings(
      cor(cid_vec[idx], acc_vec[idx], method = "spearman")
    )
  }, numeric(1))

  alpha <- (1 - conf) / 2
  ci    <- quantile(rho_boot, c(alpha, 1 - alpha), na.rm = TRUE)

  list(
    rho     = rho,
    lower   = unname(ci[[1]]),
    upper   = unname(ci[[2]]),
    p.value = pval,
    n       = n
  )
}

#' Apply SpearmanCorrelation for one model across all grid cells
#'
#' Loads pre-computed per-replicate CID and imputation accuracy data frames
#' (saved by tree_accuracy.R and imputation_analysis.R respectively), then
#' runs SpearmanCorrelation() for each grid cell.
#'
#' @param modelID       Model script name e.g. "model4".
#' @param cid_data      Data frame with columns: scenario, gridTag, repID,
#'                      modelID, median_cid. Typically loaded from the .rds
#'                      produced by analysis/05_tree_accuracy.R.
#' @param acc_data      Data frame with columns: scenario, gridTag, repID,
#'                      modelID, mean_acc. Typically loaded from the .rds
#'                      produced by analysis/06_imputation.R.
#' @param scenario      Which generative scenario to use (default "nt").
#' @param B             Bootstrap resamples (default 1000).
#' @return Data frame with one row per grid cell and columns:
#'   gridTag, modelID, rho, lower, upper, p.value, n.
#' @export
CorrelationTest <- function(modelID, cid_data, acc_data,
                            scenario = "nt", B = 1000L) {

  # Subset to model and scenario
  cid_sub <- cid_data[cid_data$modelID == modelID &
                        cid_data$scenario == scenario, ]
  acc_sub <- acc_data[acc_data$modelID == modelID &
                        acc_data$scenario == scenario, ]

  gridTags <- unique(cid_sub$gridTag)

  rows <- lapply(gridTags, function(gt) {
    cid_rep <- cid_sub$median_cid[cid_sub$gridTag == gt]
    acc_rep <- acc_sub$mean_acc[acc_sub$gridTag == gt]

    # Align by repID when both columns are present
    if (!is.null(cid_sub$repID) && !is.null(acc_sub$repID)) {
      cid_row <- cid_sub[cid_sub$gridTag == gt, ]
      acc_row <- acc_sub[acc_sub$gridTag == gt, ]
      merged  <- merge(cid_row[, c("repID", "median_cid")],
                       acc_row[, c("repID", "mean_acc")],
                       by = "repID")
      cid_rep <- merged$median_cid
      acc_rep <- merged$mean_acc
    }

    res <- SpearmanCorrelation(cid_rep, acc_rep, B = B)
    data.frame(
      gridTag = gt,
      modelID = modelID,
      rho     = res$rho,
      lower   = res$lower,
      upper   = res$upper,
      p.value = res$p.value,
      n       = res$n,
      stringsAsFactors = FALSE
    )
  })

  do.call(rbind, rows)
}

#' Produce a tidy summary of Spearman correlations across all 12 models
#'
#' Calls CorrelationTest() for each model in MODEL_IDS and binds the results
#' into a single data frame suitable for dissertation Table 6.3.
#'
#' @param cid_data  Per-replicate CID data frame (see CorrelationTest()).
#' @param acc_data  Per-replicate imputation accuracy data frame.
#' @param scenario  Generative scenario (default "nt").
#' @param model_ids Character vector of model IDs (default MODEL_IDS).
#' @param B         Bootstrap resamples (default 1000).
#' @return Data frame with columns: modelID, gridTag, rho, lower, upper,
#'   p.value, n, sig (logical: p.value < 0.05), direction ("negative",
#'   "positive", or "ns").
#' @export
CorrelationSummary <- function(cid_data, acc_data,
                               scenario  = "nt",
                               model_ids = MODEL_IDS,
                               B         = 1000L) {
  rows <- lapply(model_ids, function(mid) {
    tryCatch(
      CorrelationTest(mid, cid_data, acc_data, scenario = scenario, B = B),
      error = function(e) {
        warning("CorrelationTest failed for ", mid, ": ", conditionMessage(e))
        NULL
      }
    )
  })

  out <- do.call(rbind, rows[!vapply(rows, is.null, logical(1))])

  if (is.null(out) || nrow(out) == 0L) {
    warning("No results produced by CorrelationSummary()")
    return(invisible(NULL))
  }

  # Derived columns for table formatting
  out$sig       <- !is.na(out$p.value) & out$p.value < 0.05
  out$direction <- ifelse(
    !out$sig, "ns",
    ifelse(out$rho < 0, "negative", "positive")
  )

  # Reorder columns for readability
  col_order <- c("modelID", "gridTag", "rho", "lower", "upper",
                 "p.value", "n", "sig", "direction")
  out[, col_order[col_order %in% colnames(out)]]
}
