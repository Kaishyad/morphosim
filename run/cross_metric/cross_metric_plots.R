source("run/shared/config_theme.R")

scorecard <- safe_read_rds(PATHS$cross_metric_model)
cell_df   <- safe_read_rds(PATHS$cross_metric_cell)
rank_corr <- safe_read_rds(PATHS$cross_metric_rank_corr)

if (is.null(scorecard) || is.null(cell_df)) {
  message("Need cross_metric_model_scorecard.rds and cross_metric_gridcell.rds - ",
          "run run/cross_metric_analysis.R first. Skipping 07.")
  quit(save = "no")
}

# PLOT 1: Bump chart - rank concordance across metrics
rank_cols <- grep("^rank_", colnames(scorecard), value = TRUE)
#labels for whichever metrics happen to be present
metric_labels <- c(
  rank_median_cid          = "Tree accuracy\n(CID)",
  rank_mse_tree_len         = "Known-answer\nMSE (tree length)",
  rank_cov_error_tree_len    = "Known-answer\ncoverage error",
  rank_mean_mse_rate_loss     = "Known-answer\nMSE (rate)",
  rank_cov_error_rate_loss     = "Known-answer\ncoverage error (rate)",
  rank_pass_rate= "Convergence\npass rate",
  rank_mean_rhat_max= "Convergence\n(R-hat)",
  rank_cov_error_cgr= "CGR\ncoverage error",
  rank_prop_adequate= "PPS\nadequacy"
)
#Keep tree accuracy first, then whatever else is present in a stable order
present_cols <- c("rank_median_cid",
                  setdiff(rank_cols, "rank_median_cid"))
present_cols <- present_cols[present_cols %in% rank_cols]

if (length(present_cols) >= 2L) {
  bump_df <- scorecard %>%
    select(scenario, modelID, all_of(present_cols)) %>%
    label_models() %>%
    pivot_longer(all_of(present_cols), names_to = "metric", values_to = "rank") %>%
    mutate(
      metric = factor(metric, levels = present_cols,
                      labels = ifelse(present_cols %in% names(metric_labels),
                                       metric_labels[present_cols], present_cols))
    )

  p1 <- ggplot(bump_df, aes(x = metric, y = rank, group = modelID, color = modelID)) +
    geom_line(linewidth = 0.9, alpha = 0.75) +
    geom_point(size = 2.2) +
    scale_y_reverse(breaks = seq_len(length(unique(scorecard$modelID)))) +
    scale_color_manual(values = setNames(model_palette(length(unique(bump_df$modelID))),
                                          levels(bump_df$modelID)), name = NULL) +
    facet_wrap(~ scenario, ncol = 1) +
    labs(
      title = "Does a model's tree-accuracy rank predict its rank elsewhere?",
      subtitle = "Rank 1 (top) = best on that metric. Flat lines = consistent performer; crossing lines = tree accuracy and that metric disagree.",
      x = NULL, y = "Rank (1 = best)"
    ) +
    theme(legend.position = "right", panel.grid.major.x = element_blank())
  save_fig(p1, "16_rank_concordance_bump_chart", subdir = "cross_metric", width = 10, height = 8)
} else {
  message("Fewer than 2 rank_* columns available - skipping bump chart (plot 1).")
}

# PLOT 2: Composite scorecard heatmap - models x metrics, colored by rank
if (length(present_cols) >= 2L) {
  heat_df <- scorecard %>%
    select(scenario, modelID, all_of(present_cols)) %>%
    label_models() %>%
    pivot_longer(all_of(present_cols), names_to = "metric", values_to = "rank") %>%
    mutate(
      metric = factor(metric, levels = rev(present_cols),
                      labels = ifelse(rev(present_cols) %in% names(metric_labels),
                                       metric_labels[rev(present_cols)], rev(present_cols)))
    )

  p2 <- ggplot(heat_df, aes(x = metric, y = fct_rev(modelID), fill = rank)) +
    geom_tile(color = "white", linewidth = 0.8) +
    geom_text(aes(label = rank), size = 3) +
    scale_fill_viridis_c(option = "rocket", direction = -1, name = "Rank\n(1 = best)") +
    facet_wrap(~ scenario, ncol = 2) +
    labs(
      title = "Composite scorecard: model rank across every available metric",
      x = NULL, y = NULL
    ) +
    theme(panel.grid = element_blank(), axis.text.x = element_text(angle = 30, hjust = 1))
  save_fig(p2, "17_composite_scorecard_heatmap", subdir = "cross_metric", width = 11, height = 7)
}

# PLOT 3: Model-level scatter - mean CID vs mean known-answer MSE,
if ("avg_mse_tree_len" %in% colnames(scorecard)) {
  scat_df <- scorecard %>% label_models()

  rho_labels <- NULL
  if (!is.null(rank_corr)) {
    rho_labels <- rank_corr %>%
      filter(metric == "mse_tree_len") %>%
      mutate(label = sprintf("rho = %.2f [%.2f, %.2f]", rho, lower, upper))
  }

  p3 <- ggplot(scat_df, aes(x = avg_median_cid, y = avg_mse_tree_len, color = scenario)) +
    geom_point(size = 3) +
    ggplot2::geom_text(aes(label = modelID), size = 2.8, vjust = -0.9, show.legend = FALSE) +
    scale_color_manual(values = SCENARIO_COLORS, name = "Generative scenario") +
    facet_wrap(~ scenario, scales = "free") +
    labs(
      title = "Do models with more accurate trees also recover parameters more accurately?",
      subtitle = "One point per model (mean across grid cells). Down-and-left = better on both axes.",
      x = "Mean CID (lower = better trees)",
      y = "Mean known-answer MSE, tree length (lower = better recovery)"
    ) +
    theme(legend.position = "none")

  if (!is.null(rho_labels) && nrow(rho_labels) > 0L) {
    rho_pos <- scat_df %>% group_by(scenario) %>%
      summarise(x = min(avg_median_cid, na.rm = TRUE),
               y = max(avg_mse_tree_len, na.rm = TRUE), .groups = "drop") %>%
      left_join(rho_labels, by = "scenario")
    p3 <- p3 + geom_text(data = rho_pos, aes(x = x, y = y, label = label),
                         inherit.aes = FALSE, hjust = 0, vjust = 1, size = 3.2, fontface = "italic")
  }
  save_fig(p3, "18_model_scatter_cid_vs_known_answer_mse", subdir = "cross_metric", width = 10, height = 5.5)
} else {
  message("avg_mse_tree_len not in scorecard - skipping plot 3 (need known_answer_summary.rds).")
}

# PLOT 4: Grid-cell-level - within each model, does CID track
if ("mse_tree_len" %in% colnames(cell_df)) {
  cell_plot_df <- cell_df %>%
    filter(!is.na(median_cid), !is.na(mse_tree_len)) %>%
    label_models()

  p4 <- ggplot(cell_plot_df, aes(x = median_cid, y = mse_tree_len, color = scenario)) +
    geom_point(alpha = 0.5, size = 1.3) +
    geom_smooth(method = "lm", se = TRUE, linewidth = 0.7, color = "grey20") +
    scale_color_manual(values = SCENARIO_COLORS, name = "Generative scenario") +
    facet_wrap(~ modelID, scales = "free") +
    labs(
      title = "Within each model: does CID track known-answer MSE across parameter regimes?",
      subtitle = "One point per grid cell. A visible trend here means the parameter conditions where this model's trees\nare worse are also the conditions where its parameter estimates are worse.",
      x = "Median CID (grid cell)", y = "Known-answer MSE, tree length (grid cell)"
    ) +
    theme(legend.position = "top")
  save_fig(p4, "19_gridcell_cid_vs_known_answer_mse_by_model", subdir = "cross_metric", width = 13, height = 10)
} else {
  message("mse_tree_len not in cross-metric grid-cell table - skipping plot 4.")
}

message("\ncross_metric_plots.R complete - figures written to ", PATHS$fig_dir)
