#Fits Generalised Additive Models (GAMs) to identify parameter thresholds at
#which NT models outperform the Mk baseline in topological accuracy.

#functions:
#ComputeImprovement() - Calculates per-replicate NT improvement over Mk
#                           baseline: delta_CID = CID_Mk - CID_NT (positive = NT better).
#FitThresholdGAM()- Fits mgcv::gam(improvement ~ s(tree_length) + s(rate_ratio) + s(chars_per_taxon)) for one inference
#                           model, checks basis dimension with gam.check().
#ExtractThreshold() - Identifies the parameter value at which the GAM smooth crosses zero (NT starts to outperform Mk)
#                           using uniroot() on the predicted smooth.
#SensitivityCheck() - Re-fits GAM with doubled basis dimension k, flags models where threshold estimate shifts substantially.
#ThresholdSummary() - Applies FitThresholdGAM + ExtractThreshold across  all 12 inference models, returns tidy data frame.

#one GAM per inference model per parameter axis.

#' Compute per-replicate CID improvement of NT model over Mk baseline
#'
#' delta_CID = CID_Mk - CID_NT. Positive values mean the NT model is more
#' accurate (lower distance to true tree) than the Mk baseline for that
#' replicate.
#'
#' @param cid_data   Data frame with columns: scenario, gridTag, repID,
#'                   modelID, median_cid. Produced by analysis/tree_accuracy.R.
#' @param modelID    NT inference model to evaluate (e.g. "model4").
#' @param baselineID Mk baseline model (default "model1").
#' @param scenario   Generative scenario (default "nt").
#' @return Data frame with columns: repID, gridTag, tree_length, gain_loss,
#'   n_char, chars_per_taxon, rate_ratio, improvement.
#' @export
ComputeImprovement <- function(cid_data, modelID,
                               baselineID = "model1",
                               scenario   = "nt") {
  sub_nt <- cid_data[cid_data$modelID == modelID    & cid_data$scenario == scenario, ]
  sub_mk <- cid_data[cid_data$modelID == baselineID & cid_data$scenario == scenario, ]

  merged <- merge(
    sub_nt[, c("repID", "gridTag", "median_cid")],
    sub_mk[, c("repID", "gridTag", "median_cid")],
    by       = c("repID", "gridTag"),
    suffixes = c("_nt", "_mk")
  )

  merged$improvement <- merged$median_cid_mk - merged$median_cid_nt

  # FIX: use ScenarioGrid(scenario) not PARAM_GRID to get correct grid for scenario
  grid          <- ScenarioGrid(scenario)
  grid$gridTag  <- apply(grid, 1, function(r) GridTag(as.list(r)))
  grid_cols     <- grid[, c("tree_length", "gain_loss", "n_char", "n_taxa", "gridTag")]

  merged <- merge(merged, grid_cols, by = "gridTag", all.x = TRUE)

  merged$chars_per_taxon <- merged$n_char / merged$n_taxa
  merged$rate_ratio      <- merged$gain_loss

  merged[, c("repID", "gridTag", "tree_length", "gain_loss",
             "n_char", "chars_per_taxon", "rate_ratio", "improvement")]
}

#' Fit a threshold GAM for one inference model
#'
#' Fits:
#'   improvement ~ s(tree_length, k=k) + s(rate_ratio, k=k) +
#'                 s(chars_per_taxon, k=k)
#'
#' using mgcv::gam() with a Gaussian family (improvement is continuous).
#' Basis dimension k is checked with mgcv::gam.check(); a warning is issued
#' if any smooth is near the boundary (p < 0.05 in k-index test).
#'
#' @param improvement_df  Data frame from ComputeImprovement().
#' @param k               Requested basis dimension for all smooths (default
#'                        10). Capped per-predictor at the number of unique
#'                        observed values for that predictor (see Details).
#' @param verbose         Print gam.check() output (default FALSE).
#' @return A fitted \code{mgcv::gam} object.
#' @details If a predictor has fewer unique values than \code{k} (e.g. a
#'   coarse factorial parameter grid), its basis dimension is silently
#'   reduced to \code{max(3, n_unique - 1)} and a warning is issued, rather
#'   than letting \code{mgcv::gam()} error out.
#' @importFrom mgcv gam gam.check s
#' @export
FitThresholdGAM <- function(improvement_df, k = 10L, verbose = FALSE) {
  if (nrow(improvement_df) < k * 3L) {
    warning("Fewer observations than 3*k; reducing k to ",
            max(3L, floor(nrow(improvement_df) / 3L)))
    k <- max(3L, floor(nrow(improvement_df) / 3L))
  }

  # Cap k per-predictor at the number of unique observed values, since
  # mgcv's smooth constructors require at least k unique covariate values.
  # With a coarse factorial grid (e.g. 4 levels per axis), a global k=10
  # would request more basis functions than the data can support and
  # gam() would error out ("fewer unique covariate combinations than
  # specified maximum degrees of freedom").
  #
  # GUARD: a smooth term with very few unique x-values (k capped down to
  # 3) can still be rank-deficient once combined with the intercept and
  # other terms, producing a gam object whose underlying lm has no valid
  # 'qr' component (summary()/predict.gam() then error with "rank zero").
  # To avoid this:
  #   - n_unique < 2 (constant predictor): drop the term entirely.
  #   - n_unique in [2, 3]: use a linear term instead of a smooth (a
  #     smooth needs more distinct knots than that to be identifiable).
  #   - n_unique >= 4: smooth term as before, k capped at n_unique - 1.
  predictors <- c("tree_length", "rate_ratio", "chars_per_taxon")

  term_info <- lapply(predictors, function(p) {
    n_unique <- length(unique(improvement_df[[p]]))
    if (n_unique < 2L) {
      warning(sprintf(
        "%s is constant (1 unique value); dropping this term.", p
      ))
      list(predictor = p, n_unique = n_unique, type = "dropped", k = NA_integer_)
    } else if (n_unique < 4L) {
      warning(sprintf(
        "%s has only %d unique value(s); using a linear term instead of a smooth.",
        p, n_unique
      ))
      list(predictor = p, n_unique = n_unique, type = "linear", k = NA_integer_)
    } else {
      k_p <- min(k, max(3L, n_unique - 1L))
      if (k_p < k) {
        warning(sprintf(
          "%s has only %d unique value(s); reducing k from %d to %d for this term.",
          p, n_unique, k, k_p
        ))
      }
      list(predictor = p, n_unique = n_unique, type = "smooth", k = k_p)
    }
  })
  names(term_info) <- predictors

  term_strs <- vapply(term_info, function(ti) {
    switch(ti$type,
      dropped = NA_character_,
      linear  = ti$predictor,
      smooth  = sprintf("s(%s, k=%d)", ti$predictor, ti$k)
    )
  }, character(1))
  term_strs <- term_strs[!is.na(term_strs)]

  if (length(term_strs) == 0L) {
    stop("All predictors are constant for this model/scenario; cannot fit a GAM.")
  }

  fml <- stats::as.formula(paste("improvement ~", paste(term_strs, collapse = " + ")))

  fit <- mgcv::gam(fml, data = improvement_df, method = "REML")
  attr(fit, "term_info") <- term_info

  if (verbose) {
    mgcv::gam.check(fit)
  } else {
    chk <- tryCatch(
      utils::capture.output(mgcv::gam.check(fit)),
      error = function(e) NULL
    )
    if (!is.null(chk)) {
      low_k <- grepl("k-index.*< 1", chk)
      if (any(low_k)) {
        warning("gam.check() suggests basis dimension k may be too small; ",
                "consider increasing k or running SensitivityCheck().")
      }
    }
  }

  fit
}

#' Extract the threshold at which the GAM smooth crosses zero
#'
#' For a given parameter axis, extracts the marginal smooth from the fitted
#' GAM (holding other predictors at their medians), then uses uniroot() to
#' find the parameter value where the predicted improvement crosses zero.
#' A positive-to-zero crossing means NT starts to outperform Mk above this
#' threshold.
#'
#' @param gam_fit     A fitted mgcv::gam object from FitThresholdGAM().
#' @param predictor   Name of the smooth predictor: "tree_length",
#'                    "rate_ratio", or "chars_per_taxon".
#' @param data        The data frame used to fit the GAM (for predictor range).
#' @param n_grid      Resolution of the prediction grid (default 500).
#' @return Named list:
#'   \item{threshold}{Estimated crossing value, or NA if no crossing found.}
#'   \item{direction}{"above" (NT better above threshold) or "below", or NA.}
#'   \item{pred_range}{Numeric vector c(min, max) of predictor values searched.}
#' @importFrom mgcv predict.gam
#' @importFrom stats uniroot median
#' @export
ExtractThreshold <- function(gam_fit, predictor, data, n_grid = 500L) {
  pred_range <- range(data[[predictor]], na.rm = TRUE)
  pred_seq   <- seq(pred_range[1], pred_range[2], length.out = n_grid)

  other_preds <- setdiff(c("tree_length", "rate_ratio", "chars_per_taxon"),
                         predictor)
  newdata <- as.data.frame(
    setNames(
      lapply(other_preds, function(p) rep(median(data[[p]], na.rm = TRUE), n_grid)),
      other_preds
    )
  )
  newdata[[predictor]] <- pred_seq

  pred_vals <- as.numeric(
    mgcv::predict.gam(gam_fit, newdata = newdata, type = "response")
  )

  sign_changes <- which(diff(sign(pred_vals)) != 0)

  if (length(sign_changes) == 0L) {
    return(list(threshold  = NA_real_,
                direction  = NA_character_,
                pred_range = pred_range))
  }

  i   <- sign_changes[1]
  res <- tryCatch(
    uniroot(
      function(x) {
        newdata_pt              <- newdata[1, , drop = FALSE]
        newdata_pt[[predictor]] <- x
        as.numeric(mgcv::predict.gam(gam_fit, newdata = newdata_pt,
                                     type = "response"))
      },
      interval = c(pred_seq[i], pred_seq[i + 1]),
      tol = 1e-6
    ),
    error = function(e) NULL
  )

  if (is.null(res)) {
    return(list(threshold  = NA_real_,
                direction  = NA_character_,
                pred_range = pred_range))
  }

  threshold <- res$root
  direction <- if (pred_vals[i] < 0) "above" else "below"

  list(threshold  = threshold,
       direction  = direction,
       pred_range = pred_range)
}

#' Check threshold stability by doubling the basis dimension k
#'
#' Refits the GAM with k * 2 and compares threshold estimates on each
#' parameter axis. A shift > `tol` (on the standardised scale) is flagged
#' as unstable.
#'
#' @param improvement_df  Data frame from ComputeImprovement().
#' @param thresholds_orig Named list of thresholds from the original fit
#'                        (output of ExtractThreshold() for each axis).
#' @param k_orig          Original basis dimension (default 10).
#' @param tol             Relative tolerance for flagging instability
#'                        (default 0.10 = 10% of predictor range).
#' @return Data frame with columns: predictor, threshold_orig, threshold_2k,
#'   relative_shift, stable.
#' @export
SensitivityCheck <- function(improvement_df, thresholds_orig,
                              k_orig = 10L, tol = 0.10) {
  fit_2k <- tryCatch(
    FitThresholdGAM(improvement_df, k = k_orig * 2L, verbose = FALSE),
    error = function(e) {
      warning("SensitivityCheck: GAM refit with k=", k_orig * 2L,
              " failed: ", conditionMessage(e))
      return(NULL)
    }
  )

  predictors <- c("tree_length", "rate_ratio", "chars_per_taxon")

  rows <- lapply(predictors, function(pred) {
    t_orig <- thresholds_orig[[pred]]$threshold
    rng    <- diff(range(improvement_df[[pred]], na.rm = TRUE))

    t_2k <- if (!is.null(fit_2k)) {
      ExtractThreshold(fit_2k, pred, improvement_df)$threshold
    } else {
      NA_real_
    }

    rel_shift <- if (!is.na(t_orig) && !is.na(t_2k) && rng > 0) {
      abs(t_2k - t_orig) / rng
    } else {
      NA_real_
    }

    data.frame(
      predictor       = pred,
      threshold_orig  = t_orig,
      threshold_2k    = t_2k,
      relative_shift  = rel_shift,
      stable          = is.na(rel_shift) | rel_shift < tol,
      stringsAsFactors = FALSE
    )
  })

  do.call(rbind, rows)
}

#' Threshold summary across all 12 inference models
#'
#' For each model in model_ids:
#'   1. Computes CID improvement over Mk baseline.
#'   2. Fits a threshold GAM.
#'   3. Extracts thresholds for all three parameter axes.
#'   4. Optionally runs SensitivityCheck().
#'
#' @param cid_data      Per-replicate CID data frame.
#' @param model_ids     Model IDs to evaluate (default MODEL_IDS, excluding
#'                      "model1" as it is the Mk baseline).
#' @param baselineID    Mk baseline model ID (default "model1").
#' @param scenario      Generative scenario (default "nt").
#' @param k             GAM basis dimension (default 10).
#' @param sensitivity   Run SensitivityCheck() for each model (default TRUE).
#' @return Data frame with columns: modelID, predictor, threshold, direction,
#'   stable (if sensitivity = TRUE).
#' @export
ThresholdSummary <- function(cid_data,
                             model_ids   = setdiff(MODEL_IDS, "model1"),
                             baselineID  = "model1",
                             scenario    = "nt",
                             k           = 10L,
                             sensitivity = TRUE) {
  predictors <- c("tree_length", "rate_ratio", "chars_per_taxon")

  all_rows <- lapply(model_ids, function(mid) {
    impr_df <- tryCatch(
      ComputeImprovement(cid_data, mid, baselineID, scenario),
      error = function(e) {
        warning("ComputeImprovement failed for ", mid, ": ", conditionMessage(e))
        NULL
      }
    )
    if (is.null(impr_df) || nrow(impr_df) == 0L) return(NULL)

    fit <- tryCatch(
      FitThresholdGAM(impr_df, k = k),
      error = function(e) {
        warning("FitThresholdGAM failed for ", mid, ": ", conditionMessage(e))
        NULL
      }
    )
    if (is.null(fit)) return(NULL)

    thresholds <- setNames(
      lapply(predictors, function(pred) ExtractThreshold(fit, pred, impr_df)),
      predictors
    )

    stable_map <- if (sensitivity) {
      sens <- tryCatch(
        SensitivityCheck(impr_df, thresholds, k_orig = k),
        error = function(e) NULL
      )
      if (!is.null(sens)) {
        setNames(sens$stable, sens$predictor)
      } else {
        setNames(rep(NA, length(predictors)), predictors)
      }
    } else {
      setNames(rep(NA, length(predictors)), predictors)
    }

    rows <- lapply(predictors, function(pred) {
      thr <- thresholds[[pred]]
      data.frame(
        modelID   = mid,
        predictor = pred,
        threshold = thr$threshold,
        direction = thr$direction,
        stable    = stable_map[[pred]],
        stringsAsFactors = FALSE
      )
    })
    do.call(rbind, rows)
  })

  do.call(rbind, all_rows[!vapply(all_rows, is.null, logical(1))])
}
