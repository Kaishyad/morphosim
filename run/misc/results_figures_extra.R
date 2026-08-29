# Five extra results figures for the dissertation write-up.
# Run from the morphosim repo root:
#   Rscript run/misc/results_figures_extra.R
#
# Reuses the existing pipeline outputs under $MATRIX_DIR/results/ (see
# run/shared/config_theme.R for PATHS) and the ComputeImprovement /
# FitThresholdGAM / ExtractThreshold helpers already used by
# run/gam_threshold/gam_threshold.R -- no new data-generating logic here,
# only plotting.
#
# Output: PNG + PDF saved to TWO places so they're available in both repos:
#   1. $MATRIX_DIR/figures/misc/            (the-matrix, data repo)
#   2. <morphosim repo root>/figures/misc/  (this repo, for the write-up)
#
# Figures produced:
#   1. convergence_pass_rate_heatmap_<mk|nt>.png  -- model x grid-axis pass rate
#   2. cid_boxplots_by_model.png                  -- CID distributions by model x scenario
#   3. gam_threshold_curves_<mk|nt>.png           -- per-model marginal smooths + zero-crossing
#   4. calibration_plot.png                       -- nominal vs observed coverage, MSE as size
#   5. convergence_diagnostic_scatter_<mk|nt>.png -- ASDSF vs rank-normalised R-hat by grid cell

source("run/shared/config_theme.R")
suppressPackageStartupMessages({
  library(mgcv)
})
source("R/analysis/ThresholdGAM.R")

FIG_DIR_MATRIX <- file.path(PATHS$fig_dir, "misc")
FIG_DIR_LOCAL  <- file.path("figures", "misc")   # relative to morphosim repo root
dir.create(FIG_DIR_MATRIX, showWarnings = FALSE, recursive = TRUE)
dir.create(FIG_DIR_LOCAL,  showWarnings = FALSE, recursive = TRUE)

# Saves to both output locations in one call.
save_fig_both <- function(plot, name, width = 9, height = 6, dpi = 300) {
  for (dir in c(FIG_DIR_MATRIX, FIG_DIR_LOCAL)) {
    for (fmt in c("png", "pdf")) {
      ggsave(file.path(dir, paste0(name, ".", fmt)),
             plot = plot, width = width, height = height, dpi = dpi, bg = "white")
    }
  }
  message("Saved: ", name, " -> ", FIG_DIR_MATRIX, " and ", FIG_DIR_LOCAL)
}

# gridTag looks like "tl1.00_gl0.10_c25" (mk) or "tl1.00_gl0.10_pr1.00_c25" (nt).
# Convergence data only carries gridTag as a string, so parse the axes out of
# it directly rather than re-deriving via ScenarioGrid() (keeps this script
# self-contained and robust to partial/incomplete grids).
parse_grid_tag <- function(df) {
  df$tree_length <- as.numeric(sub(".*tl([0-9.]+)_.*", "\\1", df$gridTag))
  df$gain_loss   <- as.numeric(sub(".*gl([0-9.]+)_.*", "\\1", df$gridTag))
  df$n_char      <- as.integer(sub(".*_c([0-9]+)$", "\\1", df$gridTag))
  df$part_rate   <- suppressWarnings(as.numeric(sub(".*pr([0-9.]+)_.*", "\\1", df$gridTag)))
  df
}

# ---------------------------------------------------------------------------
# 1. Convergence pass-rate heatmap (model x characters-per-taxon, per scenario)
# ---------------------------------------------------------------------------
conv <- safe_read_rds(PATHS$convergence)

if (is.null(conv)) {
  message("Skipping figures 1 and 5 (convergence_summary.rds not found). ",
          "Run merge_convergence.R after all per-model convergence jobs finish.")
} else {
  conv <- parse_grid_tag(conv)

  for (scen in unique(conv$scenario)) {
    d <- conv[conv$scenario == scen, ]
    d <- label_models(d, "modelID")

    pass_rate <- aggregate(pass ~ modelID + n_char, data = d,
                            FUN = function(x) 100 * mean(x, na.rm = TRUE))

    p1 <- ggplot(pass_rate, aes(x = factor(n_char), y = modelID, fill = pass)) +
      geom_tile(color = "white") +
      geom_text(aes(label = sprintf("%.0f%%", pass)), size = 3, color = "grey15") +
      scale_fill_gradient2(low = "#D95F02", mid = "grey95", high = "#2C7FB8",
                            midpoint = 50, limits = c(0, 100), name = "Pass rate (%)") +
      labs(title = sprintf("Convergence pass rate by model and character count (%s)", toupper(scen)),
           subtitle = "All three criteria (R-hat, ESS, ASDSF) must pass",
           x = "Characters in matrix", y = NULL) +
      theme_matrix()

    save_fig_both(p1, sprintf("convergence_pass_rate_heatmap_%s", scen))
  }

  # -------------------------------------------------------------------------
  # 5. ASDSF vs rank-normalised R-hat diagnostic scatter, per scenario
  # -------------------------------------------------------------------------
  for (scen in unique(conv$scenario)) {
    d <- conv[conv$scenario == scen, ]
    d <- label_models(d, "modelID")

    p5 <- ggplot(d, aes(x = rhat_max, y = asdsf, color = pass)) +
      geom_point(alpha = 0.5, size = 1.3) +
      geom_vline(xintercept = 1.02, linetype = "dashed", color = "grey40") +
      geom_hline(yintercept = 0.05, linetype = "dashed", color = "grey40") +
      facet_wrap(~ modelID) +
      scale_color_manual(values = c(`TRUE` = "#2C7FB8", `FALSE` = "#D95F02"),
                          name = "Passed all criteria") +
      labs(title = sprintf("Convergence diagnostics by grid cell (%s)", toupper(scen)),
           subtitle = "Dashed lines mark the R-hat < 1.02 and ASDSF < 0.05 thresholds",
           x = "Rank-normalised R-hat (max over parameters)",
           y = "Average SD of split frequencies") +
      theme_matrix()

    save_fig_both(p5, sprintf("convergence_diagnostic_scatter_%s", scen), width = 10, height = 8)
  }
}

# ---------------------------------------------------------------------------
# 2. CID boxplots by model, faceted by generative scenario
# ---------------------------------------------------------------------------
cid_rep <- safe_read_rds(PATHS$tree_accuracy_rep)

if (is.null(cid_rep)) {
  message("Skipping figure 2 (tree_accuracy_per_rep.rds not found).")
} else {
  d <- label_models(cid_rep, "modelID")
  d$scenario_label <- ifelse(d$scenario == "mk", "Mk-generative", "NT-generative")

  p2 <- ggplot(d, aes(x = modelID, y = median_cid, fill = scenario)) +
    geom_boxplot(outlier.alpha = 0.3, outlier.size = 0.8) +
    facet_wrap(~ scenario_label, ncol = 1, scales = "free_x") +
    scale_fill_manual(values = SCENARIO_COLORS, guide = "none") +
    labs(title = "Tree accuracy (CID) by model and generative scenario",
         subtitle = "Lower CID = tree closer to the known truth",
         x = NULL, y = "Clustering Information Distance") +
    theme_matrix() +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))

  save_fig_both(p2, "cid_boxplots_by_model", height = 8)
}

# ---------------------------------------------------------------------------
# 3. GAM threshold curves: one panel per model, per scenario, per predictor
# ---------------------------------------------------------------------------
if (is.null(cid_rep)) {
  message("Skipping figure 3 (needs tree_accuracy_per_rep.rds).")
} else {
  predictors <- c("tree_length", "rate_ratio", "chars_per_taxon")
  pred_labels <- c(tree_length = "Tree length", rate_ratio = "Gain:loss ratio",
                    chars_per_taxon = "Characters per taxon")

  for (scen in c("mk", "nt")) {
    baseline_id <- BASELINE_BY_SCENARIO[[scen]]
    eval_models <- setdiff(sort(unique(cid_rep$modelID[cid_rep$scenario == scen])), baseline_id)
    if (length(eval_models) == 0) next

    curve_rows <- list()

    for (mid in eval_models) {
      impr_df <- tryCatch(ComputeImprovement(cid_rep, mid, baseline_id, scen),
                           error = function(e) NULL)
      if (is.null(impr_df) || nrow(impr_df) == 0) next

      fit <- tryCatch(FitThresholdGAM(impr_df, verbose = FALSE), error = function(e) NULL)
      if (is.null(fit)) next

      for (pred in predictors) {
        if (length(unique(impr_df[[pred]])) < 2) next

        rng <- range(impr_df[[pred]], na.rm = TRUE)
        pred_seq <- seq(rng[1], rng[2], length.out = 200)
        other <- setdiff(predictors, pred)
        newdata <- as.data.frame(setNames(
          lapply(other, function(p) rep(median(impr_df[[p]], na.rm = TRUE), 200)), other))
        newdata[[pred]] <- pred_seq

        pr <- tryCatch(predict(fit, newdata = newdata, se.fit = TRUE), error = function(e) NULL)
        if (is.null(pr)) next

        thr <- tryCatch(ExtractThreshold(fit, pred, impr_df), error = function(e) NULL)

        curve_rows[[paste(mid, pred)]] <- data.frame(
          modelID = mid, predictor = pred, x = pred_seq,
          fit = as.numeric(pr$fit), se = as.numeric(pr$se.fit),
          threshold = if (!is.null(thr)) thr$threshold else NA_real_
        )
      }
    }

    if (length(curve_rows) == 0) next
    curves <- do.call(rbind, curve_rows)
    curves <- label_models(curves, "modelID")
    curves$predictor_label <- pred_labels[curves$predictor]

    p3 <- ggplot(curves, aes(x = x, y = fit)) +
      geom_ribbon(aes(ymin = fit - 1.96 * se, ymax = fit + 1.96 * se),
                  fill = SCENARIO_COLORS[[scen]], alpha = 0.2) +
      geom_line(color = SCENARIO_COLORS[[scen]], linewidth = 0.8) +
      geom_hline(yintercept = 0, linetype = "dashed", color = "grey40") +
      geom_vline(aes(xintercept = threshold), linetype = "dotted", color = "grey20",
                 na.rm = TRUE) +
      facet_grid(modelID ~ predictor_label, scales = "free_x") +
      labs(title = sprintf("GAM-estimated improvement over baseline (%s baseline, %s-generated data)",
                            MODEL_LABELS[[baseline_id]], toupper(scen)),
           subtitle = "Shaded band = 95% CI; dotted line = zero-crossing threshold",
           x = NULL, y = expression(Delta * "CID (baseline - model)")) +
      theme_matrix()

    save_fig_both(p3, sprintf("gam_threshold_curves_%s", scen), width = 11,
                  height = 1.6 * length(eval_models) + 2)
  }
}

# ---------------------------------------------------------------------------
# 4. Calibration plot: nominal vs observed coverage, MSE as point size
# ---------------------------------------------------------------------------
ka <- safe_read_rds(PATHS$known_answer)

if (is.null(ka)) {
  message("Skipping figure 4 (known_answer_summary.rds not found).")
} else {
  cal <- rbind(
    data.frame(modelID = ka$modelID, scenario = ka$scenario,
               parameter = "Tree length", coverage = ka$cov_tree_len, mse = ka$mse_tree_len),
    data.frame(modelID = ka$modelID, scenario = ka$scenario,
               parameter = "Gain:loss ratio", coverage = ka$cov_rate_loss, mse = ka$mse_rate_loss)
  )
  cal_sum <- aggregate(cbind(coverage, mse) ~ modelID + scenario + parameter,
                        data = cal, FUN = mean, na.rm = TRUE)
  cal_sum <- label_models(cal_sum, "modelID")

  p4 <- ggplot(cal_sum, aes(x = 0.95, y = coverage, size = mse, color = scenario)) +
    geom_abline(intercept = 0, slope = 1, linetype = "dashed", color = "grey50") +
    geom_hline(yintercept = 0.95, linetype = "dotted", color = "grey60") +
    geom_point(alpha = 0.75, position = position_jitter(width = 0.01, height = 0)) +
    geom_text(aes(label = modelID), size = 2.6, vjust = -1, show.legend = FALSE) +
    facet_wrap(~ parameter) +
    scale_color_manual(values = SCENARIO_COLORS, name = "Generative scenario") +
    scale_size_continuous(name = "Mean squared error", range = c(1.5, 8)) +
    labs(title = "Calibration: observed vs nominal (95%) coverage",
         subtitle = "Point above dotted line = over-covered (conservative); below = under-covered. Larger point = higher MSE.",
         x = "Nominal coverage (95% CI target)", y = "Observed coverage") +
    theme_matrix() +
    theme(axis.text.x = element_blank(), axis.ticks.x = element_blank())

  save_fig_both(p4, "calibration_plot", width = 10, height = 6)
}

message("Done. All available figures saved under figures/misc/ in both repos.")
