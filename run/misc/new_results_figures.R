#!/usr/bin/env Rscript
# run/misc/new_results_figures.R
#
# Standalone script for the 8 recommended-but-missing figures from the
# results-chapter figure review. Run separately from run_all.R / run_viz.sh
# -- not wired into the main pipeline. Writes to figures/misc/.
#
# Run from the morphosim repo root:
#   Rscript run/misc/new_results_figures.R
#
# Each block is independent and wrapped so one missing/malformed input
# file skips only that figure, not the whole script (same safe_read_*
# pattern as the rest of run/).
#
# NOTE on #8 (GAM improvement-over-baseline plot): not included here.
# That one isn't a new chart to build, it's an existing broken one to
# debug -- every panel currently renders empty, most likely because the
# predict(gam_fit, newdata=..., se.fit=TRUE) call is being fed a newdata
# grid whose scenario/model labels don't match the fitted GAM object's
# labels, so the join silently returns zero rows rather than an error.
# Check that before touching the plotting code itself.
#
# NOTE on #9 (pass-rate table): not a chart, belongs in your write-up's
# methods/limitations as a plain table, not generated here.

suppressPackageStartupMessages({
  library(tidyverse)
  library(ggrepel)
})

source("run/shared/config_theme.R")

MISC_SUBDIR <- "misc"

# ---------------------------------------------------------------------------
# 1. Convergence quality vs. accuracy -- the headline sign-flip scatter
# ---------------------------------------------------------------------------
cross_metric_model <- safe_read_csv(file.path(PATHS$results_dir, "cross_metric", "cross_metric_model_scorecard.csv"))

if (!is.null(cross_metric_model)) {
  df <- cross_metric_model %>% label_models()

  # Fitted correlations, annotated manually per the write-up's reported values
  ann <- tibble(
    scenario = c("mk", "nt"),
    label    = c("mk: \u03c1 = \u22120.64, p = .024", "nt: \u03c1 = +0.29, p = .35 (n.s.)")
  ) %>%
    left_join(
      df %>% group_by(scenario) %>%
        summarise(x = max(avg_mean_asdsf, na.rm = TRUE) * 0.98,
                  y = max(avg_median_cid, na.rm = TRUE) * c(1, 0.9)[match(scenario, c("mk","nt"))],
                  .groups = "drop"),
      by = "scenario"
    )

  p1 <- ggplot(df, aes(avg_mean_asdsf, avg_median_cid, color = scenario)) +
    geom_point(size = 2.5, alpha = 0.85) +
    geom_smooth(method = "lm", se = TRUE, linewidth = 0.8) +
    geom_text_repel(aes(label = modelID), size = 3, show.legend = FALSE, max.overlaps = 20) +
    geom_text(data = ann, aes(x = x, y = y, label = label), inherit.aes = FALSE,
              hjust = 1, size = 3.3, fontface = "italic") +
    scale_color_manual(values = SCENARIO_COLORS) +
    labs(title = "Convergence quality vs. tree accuracy",
         subtitle = "Worse average convergence (higher ASDSF) associates with better accuracy under mk, not nt",
         x = "Mean ASDSF (higher = worse convergence)", y = "Median CID (lower = more accurate)",
         color = "Scenario") +
    theme_matrix()

  save_fig(p1, "41_convergence_vs_accuracy_scatter", subdir = MISC_SUBDIR)
} else {
  message("Skipping figure 1 (convergence vs accuracy): cross_metric_model_scorecard.csv not found")
}

# ---------------------------------------------------------------------------
# 2. M11 vs M12, matched cell-by-cell
# ---------------------------------------------------------------------------
plot_m11_vs_m12 <- function(path, scenario_label) {
  df <- safe_read_csv(path)
  if (is.null(df)) return(NULL)
  if (!all(c("M11", "M12") %in% names(df))) {
    warning(path, " missing M11/M12 columns -- skipping")
    return(NULL)
  }

  df <- df %>%
    mutate(
      winner = case_when(
        M12 < M11 ~ "M12 better",
        M12 > M11 ~ "M11 better",
        TRUE      ~ "Tie"
      ),
      scenario = scenario_label
    )

  n_total <- nrow(df)
  n_m12_better <- sum(df$winner == "M12 better")
  df
}

m11_m12_mk <- plot_m11_vs_m12(file.path(PATHS$results_dir, "tree_accuracy", "tree_similarity_table_wide_mk.csv"), "mk")
m11_m12_nt <- plot_m11_vs_m12(file.path(PATHS$results_dir, "tree_accuracy", "tree_similarity_table_wide_nt.csv"), "nt")

m11_m12_combined <- bind_rows(m11_m12_mk, m11_m12_nt)

if (nrow(m11_m12_combined) > 0) {
  counts <- m11_m12_combined %>%
    group_by(scenario) %>%
    summarise(n = n(), m12_better = sum(winner == "M12 better"), .groups = "drop") %>%
    mutate(label = sprintf("M12 better in %d/%d cells", m12_better, n))

  size_var <- if ("n_char" %in% names(m11_m12_combined)) "n_char" else NA

  p2 <- ggplot(m11_m12_combined, aes(M11, M12, color = winner)) +
    { if (!is.na(size_var)) geom_point(aes(size = .data[[size_var]]), alpha = 0.75) else geom_point(alpha = 0.75, size = 2.5) } +
    geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "grey40") +
    geom_text(data = counts, aes(x = -Inf, y = Inf, label = label),
              inherit.aes = FALSE, hjust = -0.05, vjust = 1.5, size = 3.3, fontface = "italic") +
    facet_wrap(~scenario, labeller = as_labeller(c(mk = "Mk", nt = "NT"))) +
    scale_color_manual(values = c("M12 better" = "#41AB5D", "M11 better" = "#D95F02", "Tie" = "grey60")) +
    labs(title = "M11 vs. M12, matched cell-by-cell",
         subtitle = "Points above the dashed line favour M11; below favour M12",
         x = "M11 median CID", y = "M12 median CID", color = "Winner", size = "n_char") +
    theme_matrix()

  save_fig(p2, "42_m11_vs_m12_matched_cells", subdir = MISC_SUBDIR)
} else {
  message("Skipping figure 2 (M11 vs M12): no usable tree_similarity_table_wide_* files found")
}

# ---------------------------------------------------------------------------
# 3. Coverage-failure rate by model, mk vs nt
# ---------------------------------------------------------------------------
table2 <- safe_read_csv(file.path(PATHS$results_dir, "known_answer", "table2_mk_vs_nt_comparison.csv"))

if (!is.null(table2) && all(c("modelID", "pct_below_95_mk", "pct_below_95_nt") %in% names(table2))) {
  df <- table2 %>%
    label_models() %>%
    pivot_longer(cols = c(pct_below_95_mk, pct_below_95_nt),
                names_to = "scenario", values_to = "pct_below_95") %>%
    mutate(scenario = if_else(scenario == "pct_below_95_mk", "mk", "nt"))

  order_levels <- df %>% filter(scenario == "nt") %>% arrange(desc(pct_below_95)) %>% pull(modelID)
  df <- df %>% mutate(modelID = factor(modelID, levels = unique(c(order_levels, unique(df$modelID)))))

  p3 <- ggplot(df, aes(modelID, pct_below_95, fill = scenario)) +
    geom_col(position = "dodge") +
    geom_hline(yintercept = c(0, 100), linetype = "dashed", color = "grey50", linewidth = 0.3) +
    scale_fill_manual(values = SCENARIO_COLORS) +
    labs(title = "Coverage-failure rate by model",
         subtitle = "Percent of grid cells with <95% coverage, ordered by nt failure rate",
         x = NULL, y = "% cells with <95% coverage", fill = "Scenario") +
    theme_matrix() +
    theme(axis.text.x = element_text(angle = 40, hjust = 1))

  save_fig(p3, "43_coverage_failure_rate_by_model", subdir = MISC_SUBDIR)
} else {
  message("Skipping figure 3 (coverage failure): table2_mk_vs_nt_comparison.csv not found or missing expected columns")
}

# ---------------------------------------------------------------------------
# 4. MSE vs. coverage-failure -- overconfident vs erratic typology
# ---------------------------------------------------------------------------
table10 <- safe_read_csv(file.path(PATHS$results_dir, "known_answer", "table10_robustness_summary.csv"))

if (!is.null(table10) && all(c("mean_mse", "mean_cov", "sd_cov", "modelID") %in% names(table10))) {
  df <- table10 %>%
    label_models() %>%
    mutate(coverage_failure_rate = 1 - mean_cov)

  group_col <- if ("Group" %in% names(df)) "Group" else NA

  p4 <- ggplot(df, aes(mean_mse, coverage_failure_rate)) +
    { if (!is.na(group_col)) geom_point(aes(size = sd_cov, color = .data[[group_col]]), alpha = 0.8)
      else geom_point(aes(size = sd_cov), alpha = 0.8) } +
    geom_text_repel(aes(label = modelID), size = 3, max.overlaps = 20) +
    scale_x_log10() +
    labs(title = "Miscalibration typology: overconfident vs. erratic",
         subtitle = "Bubble size = sd(coverage) across cells -- small bubbles at high failure rate indicate consistent overconfidence, not erratic behaviour",
         x = "Mean MSE (log scale)", y = "Coverage-failure rate (1 \u2212 mean coverage)",
         size = "SD(coverage)", color = "Group") +
    theme_matrix()

  save_fig(p4, "44_mse_vs_coverage_failure_typology", subdir = MISC_SUBDIR)
} else {
  message("Skipping figure 4 (MSE vs coverage failure): table10_robustness_summary.csv not found or missing expected columns")
}

# ---------------------------------------------------------------------------
# 5. Variance decomposition: grid-cell vs model (table, not a chart)
# ---------------------------------------------------------------------------
decompose_variance <- function(path, scenario_label) {
  df <- safe_read_csv(path)
  if (is.null(df)) return(NULL)

  model_cols <- intersect(names(df), MODEL_LABELS)
  model_cols <- names(df)[names(df) %in% c(MODEL_IDS, unname(MODEL_LABELS))]
  # readable tables use M1..M12-style column headers; fall back to any
  # column matching ^M\d+ if the exact label match above finds nothing
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

  grid_col <- id_cols[1]  # first non-model column as the grid-cell identifier
  fit <- aov(cid ~ factor(.data[[grid_col]]) + factor(modelID), data = long_df)
  ss <- summary(fit)[[1]][["Sum Sq"]]
  pct <- ss / sum(ss) * 100

  tibble(
    scenario   = scenario_label,
    pct_grid_cell = pct[1],
    pct_model     = pct[2],
    pct_residual  = pct[3]
  )
}

var_mk <- tryCatch(decompose_variance(file.path(PATHS$results_dir, "model_comparison", "39_readable_table_mk.csv"), "mk"),
                    error = function(e) { warning("Variance decomposition (mk) failed: ", conditionMessage(e)); NULL })
var_nt <- tryCatch(decompose_variance(file.path(PATHS$results_dir, "model_comparison", "40_readable_table_nt_part_rate_1_00.csv"), "nt"),
                    error = function(e) { warning("Variance decomposition (nt) failed: ", conditionMessage(e)); NULL })

var_decomp <- bind_rows(var_mk, var_nt)

if (nrow(var_decomp) > 0) {
  write_csv(var_decomp, file.path(PATHS$results_dir, "variance_decomposition_grid_vs_model.csv"))
  message("Saved: variance_decomposition_grid_vs_model.csv -> ", PATHS$results_dir)

  p5_df <- var_decomp %>%
    pivot_longer(cols = starts_with("pct_"), names_to = "source", values_to = "pct") %>%
    mutate(source = recode(source,
                           pct_grid_cell = "Grid cell",
                           pct_model     = "Model",
                           pct_residual  = "Residual"))

  p5 <- ggplot(p5_df, aes(scenario, pct, fill = source)) +
    geom_col() +
    labs(title = "Variance in CID attributable to grid cell vs. model choice",
         subtitle = "From aov(cid ~ gridTag + modelID) fit separately per scenario",
         x = NULL, y = "% of sum of squares", fill = "Source") +
    theme_matrix()

  save_fig(p5, "45_variance_decomposition_grid_vs_model", subdir = MISC_SUBDIR)
} else {
  message("Skipping figure 5 (variance decomposition): no usable readable_table files found, or aov() failed -- check the grid-cell id column matches expectations")
}

# ---------------------------------------------------------------------------
# 6. n_char = 200's double-edged effect on tree-length MSE
# ---------------------------------------------------------------------------
known_answer <- safe_read_csv(file.path(PATHS$results_dir, "known_answer", "known_answer_summary.csv"))

if (!is.null(known_answer) && all(c("tree_length", "mse_tree_len", "n_char") %in% names(known_answer))) {
  p6 <- ggplot(known_answer, aes(tree_length, mse_tree_len)) +
    geom_jitter(width = 0.05, alpha = 0.4, size = 1.5) +
    stat_summary(fun = mean, geom = "line", aes(group = 1), color = "#D95F02", linewidth = 1) +
    stat_summary(fun = mean, geom = "point", aes(group = 1), color = "#D95F02", size = 2.5) +
    facet_wrap(~n_char, labeller = label_both) +
    labs(title = "Tree-length MSE across the grid, by character count",
         subtitle = "n_char = 200 shows the steepest, most divergent relationship with true tree length",
         x = "True tree length", y = "MSE (tree length)") +
    theme_matrix()

  save_fig(p6, "46_nchar200_tree_length_mse_double_edge", subdir = MISC_SUBDIR)
} else {
  message("Skipping figure 6 (n_char=200 double edge): known_answer_summary.csv not found or missing expected columns")
}

# ---------------------------------------------------------------------------
# 7. Win-count composition by character count, nt scenario
# ---------------------------------------------------------------------------
nt_wide <- safe_read_csv(file.path(PATHS$results_dir, "tree_accuracy", "tree_similarity_table_wide_nt.csv"))

if (!is.null(nt_wide) && "n_char" %in% names(nt_wide)) {
  model_cols_7 <- grep("^M\\d+", names(nt_wide), value = TRUE)
  if (length(model_cols_7) > 0) {
    winners <- nt_wide %>%
      rowwise() %>%
      mutate(winner = model_cols_7[which.min(c_across(all_of(model_cols_7)))]) %>%
      ungroup() %>%
      select(n_char, winner)

    p7 <- ggplot(winners, aes(factor(n_char), fill = winner)) +
      geom_bar(position = "fill") +
      scale_y_continuous(labels = scales::percent) +
      labs(title = "Win-count composition by character count (nt scenario)",
           subtitle = "Share of grid cells won by each model, per n_char level",
           x = "n_char", y = "Share of cells won", fill = "Model") +
      theme_matrix()

    save_fig(p7, "47_win_composition_by_nchar_nt", subdir = MISC_SUBDIR)
  } else {
    message("Skipping figure 7 (win composition): no M#-style model columns found in tree_similarity_table_wide_nt.csv")
  }
} else {
  message("Skipping figure 7 (win composition): tree_similarity_table_wide_nt.csv not found or missing n_char column")
}

message("\nDone. Check messages above for any skipped figures and why.")
