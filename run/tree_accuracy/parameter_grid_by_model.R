
source("run/shared/config_theme.R")

sum_df <- safe_read_rds(PATHS$tree_accuracy_sum)
if (is.null(sum_df)) quit(save = "no")

sum_df <- sum_df %>% filter(!is.na(median_cid)) %>% label_models()

AXES <- c("tree_length", "gain_loss", "n_char")   #present in both scenarios
AXIS_LABELS <- c(tree_length = "Tree length", gain_loss = "Gain:loss ratio",
                  n_char = "Number of characters", part_rate = "Partition rate scalar")

# Marginal effect lines one axis at a time, other axes averaged
for (ax in AXES) {
  marg <- sum_df %>%
    group_by(scenario, modelID, .val = .data[[ax]]) %>%
    summarise(mean_cid = mean(median_cid, na.rm = TRUE), .groups = "drop")

  p <- ggplot(marg, aes(x = .val, y = mean_cid, color = modelID)) +
    geom_line(linewidth = 0.7) +
    geom_point(size = 1.6) +
    facet_wrap(~ scenario) +
    scale_color_manual(values = setNames(model_palette(length(unique(marg$modelID))),
                                          levels(marg$modelID)), name = NULL) +
    labs(
      title = paste0("Mean CID vs ", AXIS_LABELS[[ax]], ", by model"),
      subtitle = "Other grid axes averaged out. Lower = more accurate.",
      x = AXIS_LABELS[[ax]], y = "Mean CID"
    )
  save_fig(p, paste0("20_marginal_", ax, "_by_model"), subdir = "tree_accuracy", width = 10, height = 6)
}

# part_rate is nt-only, its own figure, not averaged into the loop above
if ("part_rate" %in% names(sum_df) && any(!is.na(sum_df$part_rate))) {
  marg_pr <- sum_df %>%
    filter(scenario == "nt", !is.na(part_rate)) %>%
    group_by(modelID, .val = part_rate) %>%
    summarise(mean_cid = mean(median_cid, na.rm = TRUE), .groups = "drop")

  p_pr <- ggplot(marg_pr, aes(x = .val, y = mean_cid, color = modelID)) +
    geom_line(linewidth = 0.8) +
    geom_point(size = 1.8) +
    scale_color_manual(values = setNames(model_palette(length(unique(marg_pr$modelID))),
                                          levels(marg_pr$modelID)), name = NULL) +
    labs(
      title = "Mean CID vs partition rate scalar, by model (nt scenario only)",
      subtitle = "part_rate only varies under the nt generative scenario. Lower CID = more accurate.",
      x = AXIS_LABELS[["part_rate"]], y = "Mean CID"
    )
  save_fig(p_pr, "21_marginal_part_rate_by_model_nt", subdir = "tree_accuracy", width = 9, height = 6)
} else {
  message("No part_rate values found -- skipping plot 21 (nt scenario grid may not have been run/merged yet).")
}

#Two-parameter interaction heatmaps, faceted by model.
interaction_heatmap <- function(data, x_ax, y_ax, subtitle, filename, width, height) {
  cell <- data %>%
    group_by(scenario, modelID, x = .data[[x_ax]], y = .data[[y_ax]]) %>%
    summarise(mean_cid = mean(median_cid, na.rm = TRUE), .groups = "drop")

  ggplot(cell, aes(x = factor(x), y = factor(y), fill = mean_cid)) +
    geom_tile(color = "white") +
    scale_fill_viridis_c(option = "magma", direction = -1, name = "Mean CID") +
    facet_wrap(~ modelID) +
    labs(
      title = paste0(AXIS_LABELS[[x_ax]], " x ", AXIS_LABELS[[y_ax]], " interaction, by model"),
      subtitle = subtitle,
      x = AXIS_LABELS[[x_ax]], y = AXIS_LABELS[[y_ax]]
    ) +
    theme(panel.grid = element_blank(), axis.text.x = element_text(angle = 40, hjust = 1)) -> p
  save_fig(p, filename, subdir = "tree_accuracy", width = width, height = height)
}

for (sc in names(BASELINE_BY_SCENARIO)) {
  interaction_heatmap(
    sum_df %>% filter(scenario == sc),
    "tree_length", "gain_loss",
    subtitle = paste0(sc, " scenario. Darker = lower (better) mean CID."),
    filename = paste0("22_interaction_tree_length_gain_loss_", sc),
    width = 11, height = 9
  )
}

if ("part_rate" %in% names(sum_df) && any(!is.na(sum_df$part_rate))) {
  interaction_heatmap(
    sum_df %>% filter(scenario == "nt", !is.na(part_rate)),
    "tree_length", "part_rate",
    subtitle = "nt scenario only. Darker = lower (better) mean CID.",
    filename = "23_interaction_tree_length_part_rate_nt",
    width = 11, height = 9
  )
}

# Main-effect sensitivity summary: for each model x grid axis,
sens_axes <- c(AXES, "part_rate")

sens_df <- bind_rows(lapply(sens_axes, function(ax) {
  sum_df %>%
    filter(!is.na(.data[[ax]])) %>%
    group_by(scenario, modelID) %>%
    summarise(
      axis  = ax,
      rho   = if (n() >= 3 && sd(.data[[ax]], na.rm = TRUE) > 0)
        suppressWarnings(cor(.data[[ax]], median_cid, method = "spearman", use = "complete.obs"))
      else NA_real_,
      .groups = "drop"
    )
}))

p_sens <- ggplot(sens_df, aes(x = axis, y = fct_rev(modelID), fill = rho)) +
  geom_tile(color = "white") +
  geom_text(aes(label = ifelse(is.na(rho), "", sprintf("%.2f", rho))), size = 2.9) +
  scale_fill_gradient2(low = "#1A9850", mid = "grey95", high = "#B2182B",
                        midpoint = 0, limits = c(-1, 1), na.value = "grey90",
                        name = "Spearman \u03c1\n(vs CID)") +
  facet_wrap(~ scenario) +
  labs(
    title = "Which grid parameter matters most to which model?",
    subtitle = "Spearman correlation of each axis with CID. Red = model gets worse as the axis increases; green = model improves.",
    x = NULL, y = NULL
  ) +
  theme(panel.grid = element_blank(), axis.text.x = element_text(angle = 30, hjust = 1))
save_fig(p_sens, "24_parameter_sensitivity_summary", subdir = "tree_accuracy", width = 9, height = 7)

# Win-region map: for the tree_length x gain_loss plane, which
win_region <- sum_df %>%
  group_by(scenario, modelID, tree_length, gain_loss) %>%
  summarise(mean_cid = mean(median_cid, na.rm = TRUE), .groups = "drop") %>%
  group_by(scenario, tree_length, gain_loss) %>%
  filter(mean_cid == min(mean_cid, na.rm = TRUE)) %>%
  slice(1) %>%
  ungroup()

p_win <- ggplot(win_region, aes(x = factor(tree_length), y = factor(gain_loss), fill = modelID)) +
  geom_tile(color = "white") +
  scale_fill_manual(values = setNames(model_palette(length(unique(win_region$modelID))),
                                       levels(win_region$modelID)), name = "Winning model") +
  facet_wrap(~ scenario) +
  labs(
    title = "Which model wins each tree_length x gain_loss region?",
    subtitle = "Lowest mean CID, averaged over part_rate and n_char, per cell",
    x = AXIS_LABELS[["tree_length"]], y = AXIS_LABELS[["gain_loss"]]
  ) +
  theme(panel.grid = element_blank())
save_fig(p_win, "25_win_region_tree_length_gain_loss", subdir = "tree_accuracy", width = 9, height = 6)

message("\nparameter_grid_by_model.R complete -- figures written to ", PATHS$fig_dir)
