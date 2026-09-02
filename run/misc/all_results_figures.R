#!/usr/bin/env Rscript
#SBATCH --ntasks=1
#SBATCH --mem=4G
#SBATCH --time=00:15:00
#SBATCH -p shared
#SBATCH --job-name=all_figures
#SBATCH --output=logs/all_figures_%j.out
#SBATCH --error=logs/all_figures_%j.err
#
# consolidated, corrected version of the two figure sets in
# new_results_figures.R (numbered 41-47) and results_figures_extra.R
# (unnumbered: heatmaps, boxplots, gam curves, calibration, diagnostic
# scatter). run from the morphosim repo root:
#   Rscript run/misc/all_results_figures.R
#
# writes png to both $MATRIX_DIR/figures/misc/ and <repo root>/figures/misc/.
# set formats = c("png","pdf") in save_fig_both() below for vector copies.

suppressPackageStartupMessages({
  library(tidyverse)
  library(mgcv)
})

source("run/shared/config_theme.R")
source("R/analysis/ThresholdGAM.R")

MISC_SUBDIR    <- "misc"
FIG_DIR_MATRIX <- file.path(PATHS$fig_dir, MISC_SUBDIR)
FIG_DIR_LOCAL  <- file.path("figures", MISC_SUBDIR)   # relative to morphosim repo root
dir.create(FIG_DIR_MATRIX, showWarnings = FALSE, recursive = TRUE)
dir.create(FIG_DIR_LOCAL,  showWarnings = FALSE, recursive = TRUE)

save_fig_both <- function(plot, name, width = 9, height = 6, dpi = 300, formats = c("png")) {
  for (dir in c(FIG_DIR_MATRIX, FIG_DIR_LOCAL)) {
    for (fmt in formats) {
      ggsave(file.path(dir, paste0(name, ".", fmt)),
             plot = plot, width = width, height = height, dpi = dpi, bg = "white")
    }
  }
  message("Saved: ", name, " -> ", FIG_DIR_MATRIX, " and ", FIG_DIR_LOCAL)
}

parse_grid_tag <- function(df) {
  df$tree_length <- as.numeric(sub(".*tl([0-9.]+)_.*", "\\1", df$gridTag))
  df$gain_loss   <- as.numeric(sub(".*gl([0-9.]+)_.*", "\\1", df$gridTag))
  df$n_char      <- as.integer(sub(".*_c([0-9]+)$", "\\1", df$gridTag))
  df$part_rate   <- suppressWarnings(as.numeric(sub(".*pr([0-9.]+)_.*", "\\1", df$gridTag)))
  df
}

# numbered series (41-47)

# 41. convergence quality vs accuracy, per grid-cell x model with a live
# spearman correlation (not model-level means)
cross_cell <- safe_read_csv(file.path(PATHS$results_dir, "cross_metric_gridcell.csv"))

if (!is.null(cross_cell) && all(c("median_cid", "mean_asdsf", "scenario", "modelID") %in% names(cross_cell))) {
  df <- cross_cell %>% label_models()

  ann <- df %>%
    group_by(scenario) %>%
    summarise(
      test = list(tryCatch(cor.test(mean_asdsf, median_cid, method = "spearman"),
                            error = function(e) NULL)),
      x = max(mean_asdsf, na.rm = TRUE) * 0.98,
      y = max(median_cid, na.rm = TRUE),
      n = n(),
      .groups = "drop"
    ) %>%
    rowwise() %>%
    mutate(label = if (!is.null(test)) {
      sprintf("%s: \u03c1 = %+.2f, p = %s, n = %d", scenario,
              test$estimate, format.pval(test$p.value, digits = 2), n)
    } else {
      sprintf("%s: correlation unavailable", scenario)
    }) %>%
    ungroup() %>%
    mutate(y = y * c(mk = 1, nt = 0.9)[scenario])

  p41 <- ggplot(df, aes(mean_asdsf, median_cid, color = scenario)) +
    geom_point(size = 1.6, alpha = 0.4) +
    geom_smooth(method = "lm", se = TRUE, linewidth = 0.8) +
    geom_text(data = ann, aes(x = x, y = y, label = label), inherit.aes = FALSE,
              hjust = 1, size = 3.3, fontface = "italic") +
    scale_color_manual(values = SCENARIO_COLORS) +
    labs(title = "Convergence quality vs. tree accuracy",
         subtitle = "Per grid-cell x model; correlation computed on all cells, not model-level means",
         x = "Mean ASDSF (higher = worse convergence)", y = "Median CID (lower = more accurate)",
         color = "Scenario") +
    theme_matrix()

  save_fig_both(p41, "41_convergence_vs_accuracy_scatter")
} else {
  message("Skipping figure 41: cross_metric_gridcell.csv not found or missing expected columns")
}

# 42. m11 vs m12, matched cell-by-cell
load_m11_m12 <- function(path, scenario_label) {
  df <- safe_read_csv(path)
  if (is.null(df)) return(NULL)
  if (!all(c("M11", "M12") %in% names(df))) {
    warning(path, " missing M11/M12 columns -- skipping")
    return(NULL)
  }
  df %>%
    mutate(
      winner = case_when(
        M12 < M11 ~ "M12 better",
        M12 > M11 ~ "M11 better",
        TRUE      ~ "Tie"
      ),
      scenario = scenario_label
    )
}

m11_m12 <- bind_rows(
  load_m11_m12(file.path(PATHS$results_dir, "tree_accuracy", "tree_similarity_table_wide_mk.csv"), "mk"),
  load_m11_m12(file.path(PATHS$results_dir, "tree_accuracy", "tree_similarity_table_wide_nt.csv"), "nt")
)

if (nrow(m11_m12) > 0) {
  counts <- m11_m12 %>%
    group_by(scenario) %>%
    summarise(n = n(), m12_better = sum(winner == "M12 better"), .groups = "drop") %>%
    mutate(label = sprintf("M12 better in %d/%d cells", m12_better, n))

  size_var <- if ("n_char" %in% names(m11_m12)) "n_char" else NA

  p42 <- ggplot(m11_m12, aes(M11, M12, color = winner)) +
    { if (!is.na(size_var)) geom_point(aes(size = .data[[size_var]]), alpha = 0.75)
      else geom_point(alpha = 0.75, size = 2.5) } +
    geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "grey40") +
    geom_text(data = counts, aes(x = -Inf, y = Inf, label = label),
              inherit.aes = FALSE, hjust = -0.05, vjust = 1.5, size = 3.3, fontface = "italic") +
    facet_wrap(~scenario, labeller = as_labeller(c(mk = "Mk", nt = "NT"))) +
    scale_color_manual(values = c("M12 better" = "#41AB5D", "M11 better" = "#D95F02", "Tie" = "grey60")) +
    labs(title = "M11 vs. M12, matched cell-by-cell",
         subtitle = "Points above the dashed line favour M11; below favour M12",
         x = "M11 median CID", y = "M12 median CID", color = "Winner", size = "n_char") +
    theme_matrix()

  save_fig_both(p42, "42_m11_vs_m12_matched_cells")
} else {
  message("Skipping figure 42: no usable tree_similarity_table_wide_* files found")
}

# 43. coverage-failure rate by model
table2 <- safe_read_csv(file.path(PATHS$results_dir, "known_answer", "table2_mk_vs_nt_comparison.csv"))

if (!is.null(table2) && all(c("modelID", "pct_below_95_mk", "pct_below_95_nt") %in% names(table2))) {
  df <- table2 %>%
    label_models() %>%
    pivot_longer(cols = c(pct_below_95_mk, pct_below_95_nt),
                names_to = "scenario", values_to = "pct_below_95") %>%
    mutate(scenario = if_else(scenario == "pct_below_95_mk", "mk", "nt"))

  order_levels <- df %>% filter(scenario == "nt") %>% arrange(desc(pct_below_95)) %>% pull(modelID)
  df <- df %>% mutate(modelID = factor(modelID, levels = unique(c(order_levels, unique(df$modelID)))))

  p43 <- ggplot(df, aes(modelID, pct_below_95, fill = scenario)) +
    geom_col(position = "dodge") +
    geom_hline(yintercept = c(0, 100), linetype = "dashed", color = "grey50", linewidth = 0.3) +
    scale_fill_manual(values = SCENARIO_COLORS) +
    labs(title = "Coverage-failure rate by model",
         subtitle = "Percent of grid cells with <95% coverage, ordered by nt failure rate",
         x = NULL, y = "% cells with <95% coverage", fill = "Scenario") +
    theme_matrix() +
    theme(axis.text.x = element_text(angle = 40, hjust = 1))

  save_fig_both(p43, "43_coverage_failure_rate_by_model")
} else {
  message("Skipping figure 43: table2_mk_vs_nt_comparison.csv not found or missing expected columns")
}

# 44. mse vs coverage-failure typology
table10 <- safe_read_csv(file.path(PATHS$results_dir, "known_answer", "table10_robustness_summary.csv"))

if (!is.null(table10) && all(c("mean_mse", "mean_cov", "sd_cov", "modelID") %in% names(table10))) {
  df <- table10 %>%
    label_models() %>%
    mutate(coverage_failure_rate = 1 - mean_cov)

  group_col <- if ("Group" %in% names(df)) "Group" else NA

  p44 <- ggplot(df, aes(mean_mse, coverage_failure_rate)) +
    { if (!is.na(group_col)) geom_point(aes(size = sd_cov, color = .data[[group_col]]), alpha = 0.8)
      else geom_point(aes(size = sd_cov), alpha = 0.8) } +
    geom_text(aes(label = modelID), size = 3,
              vjust = -0.8, check_overlap = TRUE) +
    scale_x_log10() +
    labs(title = "Miscalibration typology: overconfident vs. erratic",
         subtitle = str_wrap(
           "Bubble size = sd(coverage) across cells -- small bubbles at high failure rate indicate consistent overconfidence, not erratic behaviour",
           width = 85),
         x = "Mean MSE (log scale)", y = "Coverage-failure rate (1 \u2212 mean coverage)",
         size = "SD(coverage)", color = "Group") +
    theme_matrix()

  save_fig_both(p44, "44_mse_vs_coverage_failure_typology", width = 10, height = 6.5)
} else {
  message("Skipping figure 44: table10_robustness_summary.csv not found or missing expected columns")
}

# 45. variance decomposition: how much of cid variance is grid cell vs model
decompose_variance <- function(path, scenario_label) {
  df <- safe_read_csv(path)
  if (is.null(df)) return(NULL)

  model_cols <- names(df)[names(df) %in% c(MODEL_IDS, unname(MODEL_LABELS))]
  if (length(model_cols) == 0) {
    model_cols <- grep("^M\\d+", names(df), value = TRUE)
  }
  if (length(model_cols) == 0) {
    warning(path, ": no model columns detected -- skipping variance decomposition")
    return(NULL)
  }

  id_cols <- setdiff(names(df), model_cols)
  long_df <- df %>%
    pivot_longer(cols = all_of(model_cols), names_to = "modelID", values_to = "cid") %>%
    filter(!is.na(cid))

  grid_col <- id_cols[1]
  fit <- aov(cid ~ factor(.data[[grid_col]]) + factor(modelID), data = long_df)
  ss <- summary(fit)[[1]][["Sum Sq"]]
  pct <- ss / sum(ss) * 100

  tibble(scenario = scenario_label, pct_grid_cell = pct[1], pct_model = pct[2], pct_residual = pct[3])
}

var_decomp <- bind_rows(
  tryCatch(decompose_variance(file.path(PATHS$results_dir, "model_comparison", "39_readable_table_mk.csv"), "mk"),
           error = function(e) { warning("Variance decomposition (mk) failed: ", conditionMessage(e)); NULL }),
  tryCatch(decompose_variance(file.path(PATHS$results_dir, "model_comparison", "40_readable_table_nt_part_rate_1_00.csv"), "nt"),
           error = function(e) { warning("Variance decomposition (nt) failed: ", conditionMessage(e)); NULL })
)

if (nrow(var_decomp) > 0) {
  write_csv(var_decomp, file.path(PATHS$results_dir, "variance_decomposition_grid_vs_model.csv"))

  p45_df <- var_decomp %>%
    pivot_longer(cols = starts_with("pct_"), names_to = "source", values_to = "pct") %>%
    mutate(source = recode(source, pct_grid_cell = "Grid cell", pct_model = "Model", pct_residual = "Residual"))

  p45 <- ggplot(p45_df, aes(scenario, pct, fill = source)) +
    geom_col() +
    labs(title = "Variance in CID attributable to grid cell vs. model choice",
         subtitle = "From aov(cid ~ gridTag + modelID) fit separately per scenario",
         x = NULL, y = "% of sum of squares", fill = "Source") +
    theme_matrix()

  save_fig_both(p45, "45_variance_decomposition_grid_vs_model")
} else {
  message("Skipping figure 45: no usable readable_table files found, or aov() failed")
}

# 46. n_char=200 double-edge on tree-length mse; log scale + loess to show
# the heteroscedastic fan-out that a linear mean trend would hide
known_answer <- safe_read_csv(file.path(PATHS$results_dir, "known_answer", "known_answer_summary.csv"))

if (!is.null(known_answer) && all(c("tree_length", "mse_tree_len", "n_char") %in% names(known_answer))) {
  p46 <- ggplot(known_answer, aes(tree_length, mse_tree_len)) +
    geom_jitter(width = 0.05, alpha = 0.35, size = 1.3) +
    geom_smooth(method = "loess", se = TRUE, color = "#D95F02", linewidth = 1, span = 0.9) +
    scale_y_log10() +
    facet_wrap(~n_char, labeller = label_both) +
    labs(title = "Tree-length MSE across the grid, by character count",
         subtitle = "Log-scaled y-axis + loess smooth (not a linear mean) to show the heteroscedastic fan-out, especially at n_char = 200",
         x = "True tree length", y = "MSE (tree length, log scale)") +
    theme_matrix()

  save_fig_both(p46, "46_nchar200_tree_length_mse_double_edge")
} else {
  message("Skipping figure 46: known_answer_summary.csv not found or missing expected columns")
}

# 47. win-count composition by character count, mk vs nt faceted side by side
win_comp <- function(path, scenario_label) {
  df <- safe_read_csv(path)
  if (is.null(df) || !("n_char" %in% names(df))) return(NULL)
  model_cols <- grep("^M\\d+", names(df), value = TRUE)
  if (length(model_cols) == 0) return(NULL)

  df %>%
    rowwise() %>%
    mutate(winner = model_cols[which.min(c_across(all_of(model_cols)))]) %>%
    ungroup() %>%
    select(n_char, winner) %>%
    mutate(scenario = scenario_label)
}

win_all <- bind_rows(
  win_comp(file.path(PATHS$results_dir, "tree_accuracy", "tree_similarity_table_wide_mk.csv"), "mk"),
  win_comp(file.path(PATHS$results_dir, "tree_accuracy", "tree_similarity_table_wide_nt.csv"), "nt")
)

if (nrow(win_all) > 0) {
  p47 <- ggplot(win_all, aes(factor(n_char), fill = winner)) +
    geom_bar(position = "fill") +
    facet_wrap(~scenario, labeller = as_labeller(c(mk = "Mk", nt = "NT"))) +
    scale_y_continuous(labels = scales::percent) +
    labs(title = "Win-count composition by character count",
         subtitle = "Share of grid cells won by each model, per n_char level, mk vs nt",
         x = "n_char", y = "Share of cells won", fill = "Model") +
    theme_matrix()

  save_fig_both(p47, "47_win_composition_by_nchar", width = 11)
} else {
  message("Skipping figure 47: no usable tree_similarity_table_wide_* files found")
}

# unnumbered series, carried over from results_figures_extra.R

# a. convergence pass-rate heatmap (model x n_char, per scenario)
conv <- safe_read_rds(PATHS$convergence)

if (is.null(conv)) {
  message("Skipping heatmap/diagnostic-scatter figures: convergence_summary.rds not found. ",
          "Run merge_convergence.R after all per-model convergence jobs finish.")
} else {
  conv <- parse_grid_tag(conv)

  for (scen in unique(conv$scenario)) {
    d <- conv[conv$scenario == scen, ]
    d <- label_models(d, "modelID")

    pass_rate <- aggregate(pass ~ modelID + n_char, data = d,
                            FUN = function(x) 100 * mean(x, na.rm = TRUE))

    pA <- ggplot(pass_rate, aes(x = factor(n_char), y = modelID, fill = pass)) +
      geom_tile(color = "white") +
      geom_text(aes(label = sprintf("%.0f%%", pass)), size = 3, color = "grey15") +
      scale_fill_gradient2(low = "#D95F02", mid = "grey95", high = "#2C7FB8",
                            midpoint = 50, limits = c(0, 100), name = "Pass rate (%)") +
      labs(title = sprintf("Convergence pass rate by model and character count (%s)", toupper(scen)),
           subtitle = "All three criteria (R-hat, ESS, ASDSF) must pass",
           x = "Characters in matrix", y = NULL) +
      theme_matrix()

    save_fig_both(pA, sprintf("convergence_pass_rate_heatmap_%s", scen))
  }

  for (scen in unique(conv$scenario)) {
    d <- conv[conv$scenario == scen, ]
    d <- label_models(d, "modelID")

    pB <- ggplot(d, aes(x = rhat_max, y = asdsf, color = pass)) +
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

    save_fig_both(pB, sprintf("convergence_diagnostic_scatter_%s", scen), width = 10, height = 8)
  }
}

# b. cid boxplots by model, faceted by generative scenario
cid_rep <- safe_read_rds(PATHS$tree_accuracy_rep)

if (is.null(cid_rep)) {
  message("Skipping CID boxplots: tree_accuracy_per_rep.rds not found.")
} else {
  d <- label_models(cid_rep, "modelID")
  d$scenario_label <- ifelse(d$scenario == "mk", "Mk-generative", "NT-generative")

  pC <- ggplot(d, aes(x = modelID, y = median_cid, fill = scenario)) +
    geom_boxplot(outlier.alpha = 0.3, outlier.size = 0.8) +
    facet_wrap(~ scenario_label, ncol = 1, scales = "free_x") +
    scale_fill_manual(values = SCENARIO_COLORS, guide = "none") +
    labs(title = "Tree accuracy (CID) by model and generative scenario",
         subtitle = "Lower CID = tree closer to the known truth",
         x = NULL, y = "Clustering Information Distance") +
    theme_matrix() +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))

  save_fig_both(pC, "cid_boxplots_by_model", height = 8)
}

# c. gam threshold curves
if (is.null(cid_rep)) {
  message("Skipping GAM threshold curves: needs tree_accuracy_per_rep.rds.")
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
      impr_df <- tryCatch(ComputeImprovement(cid_rep, mid, baseline_id, scen), error = function(e) NULL)
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

    pD <- ggplot(curves, aes(x = x, y = fit)) +
      geom_ribbon(aes(ymin = fit - 1.96 * se, ymax = fit + 1.96 * se),
                  fill = SCENARIO_COLORS[[scen]], alpha = 0.2) +
      geom_line(color = SCENARIO_COLORS[[scen]], linewidth = 0.8) +
      geom_hline(yintercept = 0, linetype = "dashed", color = "grey40") +
      geom_vline(aes(xintercept = threshold), linetype = "dotted", color = "grey20", na.rm = TRUE) +
      facet_grid(modelID ~ predictor_label, scales = "free_x") +
      labs(title = sprintf("GAM-estimated improvement over baseline (%s baseline, %s-generated data)",
                            MODEL_LABELS[[baseline_id]], toupper(scen)),
           subtitle = "Shaded band = 95% CI; dotted line = zero-crossing threshold",
           x = NULL, y = expression(Delta * "CID (baseline - model)")) +
      theme_matrix()

    save_fig_both(pD, sprintf("gam_threshold_curves_%s", scen), width = 11,
                  height = 1.6 * length(eval_models) + 2)
  }
}

# d. calibration plot: observed vs nominal coverage
ka <- safe_read_rds(PATHS$known_answer)

if (is.null(ka)) {
  message("Skipping calibration plot: known_answer_summary.rds not found.")
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

  pE <- ggplot(cal_sum, aes(x = 0.95, y = coverage, size = mse, color = scenario)) +
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

  save_fig_both(pE, "calibration_plot", width = 10, height = 6)
}

message("\nDone. Check messages above for any skipped figures and why.")
