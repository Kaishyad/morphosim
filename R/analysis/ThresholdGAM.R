# fits generalised additive models (gams, wood 2017) to identify parameter thresholds at which each model outperforms the scenario baseline in topological accuracy

#per-replicate cid improvement of a model over its scenario baseline:
#delta_cid = cid_baseline - cid_model. positive values mean the evaluated
#model is more accurate (lower distance to true tree) than the baseline.
ComputeImprovement <- function(cid_data, modelID, baselineID = NULL, scenario   = "nt") {
  if (is.null(baselineID)) {
    baselineID <- BASELINE_BY_SCENARIO[[scenario]]
    if (is.null(baselineID)) {
      stop("No default baseline known for scenario '", scenario,
           "'; pass baselineID explicitly.")
    }
  }

  sub_nt <- cid_data[cid_data$modelID == modelID    & cid_data$scenario == scenario, ]
  sub_mk <- cid_data[cid_data$modelID == baselineID & cid_data$scenario == scenario, ]

  merged <- merge(
    sub_nt[, c("repID", "gridTag", "median_cid")],
    sub_mk[, c("repID", "gridTag", "median_cid")],
    by       = c("repID", "gridTag"),
    suffixes = c("_nt", "_mk")
  )

  merged$improvement <- merged$median_cid_mk - merged$median_cid_nt

  grid<- ScenarioGrid(scenario)
  grid$gridTag  <- apply(grid, 1, function(r) GridTag(as.list(r)))
  grid_cols     <- grid[, c("tree_length", "gain_loss", "n_char", "n_taxa", "gridTag")]

  merged <- merge(merged, grid_cols, by = "gridTag", all.x = TRUE)

  merged$chars_per_taxon <- merged$n_char / merged$n_taxa
  merged$rate_ratio      <- merged$gain_loss

  merged[, c("repID", "gridTag", "tree_length", "gain_loss", "n_char", "chars_per_taxon", "rate_ratio", "improvement")]
}

# fits improvement ~ s(tree_length) + s(rate_ratio) + s(chars_per_taxon) via
# mgcv::gam() (gaussian family). if a predictor has fewer unique values than
# k (e.g. a coarse factorial grid), its basis dimension is reduced to
# max(3, n_unique - 1), or the term is linearised/dropped below 4/2 unique
# values, rather than letting gam() error out. gam.check() is run to flag a
# basis dimension that's too small (k-index test).
FitThresholdGAM <- function(improvement_df, k = 10L, verbose = FALSE) {
  if (nrow(improvement_df) < k * 3L) {
    warning("Fewer observations than 3*k; reducing k to ",
            max(3L, floor(nrow(improvement_df) / 3L)))
    k <- max(3L, floor(nrow(improvement_df) / 3L))
  }

  # cap k per-predictor at unique observed values (mgcv requires >= k unique
  # covariate values per smooth); below 4 unique values a smooth is
  # rank-deficient, so fall back to linear (2-3 values) or drop (constant)
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

#extracts the threshold at which the gam smooth crosses zero. for a given parameter axis, takes the marginal smooth from the fitted gam (holding
#other predictors at their medians), then uses uniroot() to find the parameter value where predicted improvement crosses zero - a
#positive-to-zero crossing means nt starts to outperform mk above it.
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

#checks threshold stability by refitting with k doubled and comparing threshold estimates on each axis; a shift > tol (relative to the  predictor's range) is stopped as unstable
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

# threshold summary across all 12 inference models computes cid improvement over the scenario baseline, fits a threshold gam, extracts thresholds for
# all three parameter axes, and optionally runs SensitivityCheck(). model_ids normal to all models except the scenario's own baseline (model1 for mk, model8 for nt).
ThresholdSummary <- function(cid_data,
                             model_ids   = NULL,
                             baselineID  = NULL,
                             scenario    = "nt",
                             k           = 10L,
                             sensitivity = TRUE) {
  if (is.null(baselineID)) {
    baselineID <- BASELINE_BY_SCENARIO[[scenario]]
    if (is.null(baselineID)) {
      stop("No default baseline known for scenario '", scenario,
           "'; pass baselineID explicitly.")
    }
  }
  if (is.null(model_ids)) {
    model_ids <- setdiff(MODEL_IDS, baselineID)
  }

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
