# Cross-metric analysis: does tree accuracy (CID) track other measures of
# model performance -- MCMC convergence, known-answer parameter recovery,
# and CGR/SBC calibration?

#' Aggregate per-replicate convergence diagnostics to grid-cell level
#'
#' @param conv_df Data frame from convergence_summary.rds (one row per
#'   scenario/gridTag/repID/modelID).
#' @return Data frame with one row per scenario/gridTag/modelID: pass_rate,
#'   mean_rhat_max, mean_ess_min, mean_asdsf, mean_tree_ess.
#' @export
AggregateConvergence <- function(conv_df) {
  keys <- unique(conv_df[, c("scenario", "gridTag", "modelID")])
  rows <- lapply(seq_len(nrow(keys)), function(i) {
    k   <- keys[i, ]
    sub <- conv_df[conv_df$scenario == k$scenario &
                   conv_df$gridTag  == k$gridTag  &
                   conv_df$modelID  == k$modelID, ]
    data.frame(
      scenario      = k$scenario,
      gridTag       = k$gridTag,
      modelID       = k$modelID,
      pass_rate     = mean(sub$pass, na.rm = TRUE),
      mean_rhat_max = mean(sub$rhat_max, na.rm = TRUE),
      mean_ess_min  = mean(sub$ess_min,  na.rm = TRUE),
      mean_asdsf    = mean(sub$asdsf,    na.rm = TRUE),
      mean_tree_ess = mean(sub$tree_ess, na.rm = TRUE),
      n_reps_conv   = nrow(sub),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

#' Aggregate known-answer coverage/MSE to grid-cell level
#'
#' known_answer_summary.rds has one row per (scenario, gridTag, modelID,
#' rate_param) for two-partition models (gain_loss_neo and gain_loss_trans
#' logged separately) -- this collapses those to a single row per
#' scenario/gridTag/modelID by averaging across rate_param rows, and adds
#' coverage-error columns (|coverage - 0.95|; 0 = perfectly calibrated).
#'
#' @param ka_df Data frame from known_answer_summary.rds.
#' @return Data frame with one row per scenario/gridTag/modelID.
#' @export
AggregateKnownAnswer <- function(ka_df) {
  keys <- unique(ka_df[, c("scenario", "gridTag", "modelID")])
  rows <- lapply(seq_len(nrow(keys)), function(i) {
    k   <- keys[i, ]
    sub <- ka_df[ka_df$scenario == k$scenario &
                 ka_df$gridTag  == k$gridTag  &
                 ka_df$modelID  == k$modelID, ]
    data.frame(
      scenario            = k$scenario,
      gridTag             = k$gridTag,
      modelID             = k$modelID,
      cov_tree_len        = sub$cov_tree_len[1],   # identical across rate_param rows
      mse_tree_len        = sub$mse_tree_len[1],
      cov_error_tree_len  = abs(sub$cov_tree_len[1] - 0.95),
      mean_cov_rate_loss  = mean(sub$cov_rate_loss, na.rm = TRUE),
      mean_mse_rate_loss  = mean(sub$mse_rate_loss, na.rm = TRUE),
      cov_error_rate_loss = abs(mean(sub$cov_rate_loss, na.rm = TRUE) - 0.95),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

#' Aggregate CGR/SBC coverage to grid-cell level
#'
#' cgr_coverage.rds has one row per (scenario, modelID, gridTag, parameter)
#' -- this collapses across parameters the same way AggregateKnownAnswer()
#' does for known_answer_summary.rds.
#'
#' @param cgr_df Data frame from cgr_coverage.rds.
#' @return Data frame with one row per scenario/gridTag/modelID.
#' @export
AggregateCGR <- function(cgr_df) {
  keys <- unique(cgr_df[, c("scenario", "gridTag", "modelID")])
  rows <- lapply(seq_len(nrow(keys)), function(i) {
    k   <- keys[i, ]
    sub <- cgr_df[cgr_df$scenario == k$scenario &
                  cgr_df$gridTag  == k$gridTag  &
                  cgr_df$modelID  == k$modelID, ]
    data.frame(
      scenario           = k$scenario,
      gridTag            = k$gridTag,
      modelID            = k$modelID,
      mean_cgr_coverage  = mean(sub$coverage_rate, na.rm = TRUE),
      cov_error_cgr      = abs(mean(sub$coverage_rate, na.rm = TRUE) - 0.95),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

#' Build the combined cross-metric table at (scenario, gridTag, modelID) grain
#'
#' Left-joins tree accuracy onto convergence, known-answer, CGR, and (if
#' supplied) PPS adequacy. Any input left NULL is simply skipped -- e.g. if
#' PPS adequacy hasn't been run yet, pass pps_df = NULL (the default) and
#' those columns will be absent rather than the function erroring out.
#'
#' @param tree_acc_summary tree_accuracy_summary.rds (grid-cell level; must
#'   have scenario, gridTag, modelID, median_cid, iqr_cid).
#' @param conv_df    convergence_summary.rds (per-replicate; aggregated
#'   internally via AggregateConvergence()). NULL to skip.
#' @param ka_df       known_answer_summary.rds. NULL to skip.
#' @param cgr_df      cgr_coverage.rds. NULL to skip.
#' @param pps_df      pps_adequacy rds/data frame with columns scenario,
#'   gridTag, modelID, prop_adequate (already grid-cell level). NULL to skip.
#' @return Data frame, one row per (scenario, gridTag, modelID) present in
#'   tree_acc_summary, with whatever other-metric columns were available
#'   joined on (NA where a source was NULL or had no matching row).
#' @export
BuildCrossMetricTable <- function(tree_acc_summary,
                                  conv_df = NULL,
                                  ka_df   = NULL,
                                  cgr_df  = NULL,
                                  pps_df  = NULL) {
  out <- tree_acc_summary[, intersect(
    c("scenario", "gridTag", "modelID", "median_cid", "iqr_cid", "n_reps",
      "tree_length", "gain_loss", "n_char", "n_taxa", "part_rate"),
    colnames(tree_acc_summary)
  )]

  .LeftJoin <- function(x, y) {
    if (is.null(y) || nrow(y) == 0L) return(x)
    merge(x, y, by = c("scenario", "gridTag", "modelID"), all.x = TRUE)
  }

  if (!is.null(conv_df)) out <- .LeftJoin(out, AggregateConvergence(conv_df))
  if (!is.null(ka_df))   out <- .LeftJoin(out, AggregateKnownAnswer(ka_df))
  if (!is.null(cgr_df))  out <- .LeftJoin(out, AggregateCGR(cgr_df))
  if (!is.null(pps_df))  out <- .LeftJoin(out, pps_df[, intersect(
    c("scenario", "gridTag", "modelID", "prop_adequate"), colnames(pps_df)
  )])

  out
}

#' Model-level scorecard: one row per (scenario, modelID) with every metric
#' averaged across grid cells, plus a within-scenario rank for each metric.
#'
#' Rank 1 = best for every metric (so e.g. mse_tree_len is ranked ascending,
#' but pass_rate is ranked descending) -- this makes cross-metric rank
#' correlation directly interpretable: "does a model's tree-accuracy rank
#' predict its rank on other axes?"
#'
#' @param cross_df Output of BuildCrossMetricTable().
#' @return Data frame, one row per scenario/modelID, with mean_* columns and
#'   matching rank_* columns for every metric present.
#' @export
ModelLevelScorecard <- function(cross_df) {
  metric_cols <- intersect(c(
    "median_cid", "mean_rhat_max", "mean_ess_min", "mean_asdsf",
    "pass_rate", "mse_tree_len", "cov_error_tree_len",
    "mean_mse_rate_loss", "cov_error_rate_loss", "cov_error_cgr",
    "prop_adequate"
  ), colnames(cross_df))

  # Direction: TRUE = lower is better (rank ascending), FALSE = higher is
  # better (rank descending).
  lower_is_better <- c(
    median_cid          = TRUE,
    mean_rhat_max        = TRUE,
    mean_ess_min          = FALSE,
    mean_asdsf            = TRUE,
    pass_rate              = FALSE,
    mse_tree_len            = TRUE,
    cov_error_tree_len       = TRUE,
    mean_mse_rate_loss        = TRUE,
    cov_error_rate_loss        = TRUE,
    cov_error_cgr                = TRUE,
    prop_adequate                 = FALSE
  )

  # Each metric m gets one averaged column "avg_<m>" (e.g. avg_median_cid,
  # avg_mean_rhat_max -- yes that reads a little redundantly for columns
  # that already say "mean_" in their own name, but it keeps the naming
  # rule for this function uniform and unambiguous: "avg_" always means
  # "averaged across grid cells by ModelLevelScorecard()", regardless of
  # what the underlying per-cell column was already called.
  keys <- unique(cross_df[, c("scenario", "modelID")])
  rows <- lapply(seq_len(nrow(keys)), function(i) {
    k   <- keys[i, ]
    sub <- cross_df[cross_df$scenario == k$scenario & cross_df$modelID == k$modelID, ]
    row <- data.frame(scenario = k$scenario, modelID = k$modelID,
                      n_grid_cells = nrow(sub), stringsAsFactors = FALSE)
    for (m in metric_cols) {
      row[[paste0("avg_", m)]] <- mean(sub[[m]], na.rm = TRUE)
    }
    row
  })
  scorecard <- do.call(rbind, rows)

  # Rank within scenario for each avg_* column. Rank 1 = best.
  for (m in metric_cols) {
    avg_col  <- paste0("avg_",  m)
    rank_col <- paste0("rank_", m)
    ascending <- if (m %in% names(lower_is_better)) lower_is_better[[m]] else TRUE
    scorecard[[rank_col]] <- ave(
      scorecard[[avg_col]], scorecard$scenario,
      FUN = function(x) rank(if (ascending) x else -x, na.last = "keep")
    )
  }

  scorecard[order(scorecard$scenario, scorecard$rank_median_cid), ]
}

#' Spearman rank correlation between tree-accuracy rank and every other
#' metric's rank, across models, within each scenario.
#'
#' This is the direct answer to "do models that produce better trees also
#' have better results?" at the model-comparison grain. Reuses
#' SpearmanCorrelation() (R/analysis/Correlation.R, now a generic helper) for the bootstrap CI.
#' n is small here (<=12 per scenario) -- report rho and the CI, not just a
#' p-value, and treat this as descriptive/exploratory rather than a
#' confirmatory test (see docs/tree_accuracy_methodology.md).
#'
#' @param scorecard Output of ModelLevelScorecard().
#' @param B Bootstrap resamples for the CI (default 1000).
#' @return Data frame: scenario, metric, rho, lower, upper, p.value, n.
#' @export
ModelRankCorrelations <- function(scorecard, B = 1000L) {
  rank_cols <- grep("^rank_", colnames(scorecard), value = TRUE)
  rank_cols <- setdiff(rank_cols, "rank_median_cid")

  rows <- lapply(unique(scorecard$scenario), function(scen) {
    sub <- scorecard[scorecard$scenario == scen, ]
    inner <- lapply(rank_cols, function(rc) {
      res <- SpearmanCorrelation(sub$rank_median_cid, sub[[rc]], B = B)
      data.frame(
        scenario = scen,
        metric   = sub("^rank_", "", rc),
        rho      = res$rho,
        lower    = res$lower,
        upper    = res$upper,
        p.value  = res$p.value,
        n        = res$n,
        stringsAsFactors = FALSE
      )
    })
    do.call(rbind, inner)
  })
  do.call(rbind, rows)
}

#' Grid-cell-level Spearman correlations between CID and every other metric,
#' computed separately for each model.
#'
#' Complementary to ModelRankCorrelations(): within a single model, across
#' the grid cells it was run on, does the CID pattern track the other
#' metrics? Much higher n per test than the model-level comparison, at the
#' cost of answering a within-model rather than between-model question.
#'
#' @param cross_df Output of BuildCrossMetricTable().
#' @param B Bootstrap resamples for the CI (default 1000).
#' @return Data frame: scenario, modelID, metric, rho, lower, upper,
#'   p.value, n.
#' @export
GridCellCorrelations <- function(cross_df, B = 1000L) {
  metric_cols <- intersect(c(
    "mean_rhat_max", "mean_ess_min", "mean_asdsf", "pass_rate",
    "mse_tree_len", "cov_error_tree_len", "mean_mse_rate_loss",
    "cov_error_rate_loss", "cov_error_cgr", "prop_adequate"
  ), colnames(cross_df))

  combos <- unique(cross_df[, c("scenario", "modelID")])
  rows <- lapply(seq_len(nrow(combos)), function(i) {
    k   <- combos[i, ]
    sub <- cross_df[cross_df$scenario == k$scenario & cross_df$modelID == k$modelID, ]
    inner <- lapply(metric_cols, function(m) {
      res <- tryCatch(
        SpearmanCorrelation(sub$median_cid, sub[[m]], B = B),
        error = function(e) list(rho = NA_real_, lower = NA_real_,
                                 upper = NA_real_, p.value = NA_real_, n = 0L)
      )
      data.frame(
        scenario = k$scenario,
        modelID  = k$modelID,
        metric   = m,
        rho      = res$rho,
        lower    = res$lower,
        upper    = res$upper,
        p.value  = res$p.value,
        n        = res$n,
        stringsAsFactors = FALSE
      )
    })
    do.call(rbind, inner)
  })
  do.call(rbind, rows)
}
