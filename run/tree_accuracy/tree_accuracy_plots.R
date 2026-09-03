source("run/shared/config_theme.R")

rep_df <- safe_read_rds(PATHS$tree_accuracy_rep)
if (is.null(rep_df)) quit(save = "no")

rep_df <- rep_df %>%
  filter(!is.na(median_cid)) %>%
  rename(cid = median_cid) %>%
  label_models()

# plot 1: compact dot-and-errorbar (median + IQR), replacing the 24-box
# boxplot. Same information (median, IQR) as the boxplot and the summary
# table, but roughly a third of the vertical space and much faster to
# scan -- the boxplot's per-box width/whisker detail wasn't carrying any
# extra signal beyond what's already reported numerically in the text.
# Colored per model (not just per scenario) so each model keeps a
# consistent identity across the two facets.

model_levels <- levels(rep_df$modelID)
model_colors <- setNames(model_palette(length(model_levels)), model_levels)

summary_df <- rep_df %>%
  group_by(modelID, scenario) %>%
  summarise(
    median_cid = median(cid, na.rm = TRUE),
    q1 = quantile(cid, 0.25, na.rm = TRUE),
    q3 = quantile(cid, 0.75, na.rm = TRUE),
    .groups = "drop"
  )

# order every facet by the same reference ranking (NT-scenario median)
# so the model order stays identical left-to-right across both panels
nt_order <- summary_df %>%
  filter(scenario == "nt") %>%
  arrange(median_cid) %>%
  pull(modelID)

summary_df <- summary_df %>%
  mutate(
    modelID = factor(modelID, levels = rev(nt_order)),
    scenario_label = recode(scenario, mk = "Mk-generated", nt = "NT-generated")
  )

p1 <- ggplot(summary_df, aes(x = modelID, y = median_cid, colour = modelID)) +
  geom_errorbar(aes(ymin = q1, ymax = q3), width = 0, linewidth = 0.9) +
  geom_point(size = 3) +
  scale_colour_manual(values = model_colors, guide = "none") +
  coord_flip() +
  facet_wrap(~scenario_label) +
  labs(
    title = "Tree accuracy (Clustering Information Distance) by model",
    subtitle = "Point = median CID, bar = interquartile range. One panel per generative scenario.",
    x = NULL, y = "Clustering Information Distance (CID)"
  )
save_fig(p1, "01_cid_by_model_scenario", subdir = "tree_accuracy", height = 6, width = 9)

# plot 2: delta-cid relative to the scenario-appropriate baseline
delta_list <- lapply(names(BASELINE_BY_SCENARIO), function(sc) {
  base_id  <- BASELINE_BY_SCENARIO[[sc]]
  sc_df    <- rep_df %>% filter(scenario == sc)
  
  base_df <- sc_df %>%
    filter(modelID == MODEL_LABELS[[base_id]]) %>%
    group_by(gridTag, repID) %>%
    summarise(baseline_cid = mean(cid), .groups = "drop")
  
  sc_df %>%
    filter(modelID != MODEL_LABELS[[base_id]]) %>%
    inner_join(base_df, by = c("gridTag", "repID")) %>%
    mutate(delta_cid = cid - baseline_cid,   # negative = better than baseline
           baseline_label = MODEL_LABELS[[base_id]])
})
delta_df <- bind_rows(delta_list)

p2 <- ggplot(delta_df, aes(x = modelID, y = delta_cid, fill = scenario)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "grey40") +
  geom_boxplot(outlier.alpha = 0.3, width = 0.6, position = position_dodge(0.7)) +
  scale_fill_manual(values = SCENARIO_COLORS, name = "Generative scenario") +
  coord_flip() +
  labs(
    title = "Accuracy relative to each scenario's own baseline",
    subtitle = paste0(
      "mk models vs ", MODEL_LABELS[["model1"]], "  |  nt models vs ", MODEL_LABELS[["model8"]],
      ". Below the dashed line = more accurate than that scenario's baseline."
    ),
    x = NULL, y = expression(Delta*" CID  (model - scenario baseline)")
  )
save_fig(p2, "02_delta_cid_vs_scenario_baseline", subdir = "tree_accuracy", height = 6.5)

# plot 3: model ranking heatmap - mean cid, model x scenario
rank_df <- rep_df %>%
  group_by(modelID, scenario) %>%
  summarise(mean_cid = mean(cid), .groups = "drop") %>%
  group_by(scenario) %>%
  mutate(rank = rank(mean_cid)) %>%
  ungroup()

p3 <- ggplot(rank_df, aes(x = scenario, y = fct_rev(modelID), fill = mean_cid)) +
  geom_tile(color = "white", linewidth = 0.8) +
  geom_text(aes(label = sprintf("%.3f\n(#%d)", mean_cid, rank)), size = 3, lineheight = 0.9) +
  scale_fill_viridis_c(option = "magma", direction = -1, name = "Mean CID") +
  labs(
    title = "Model ranking by mean tree accuracy",
    subtitle = "Rank shown in parentheses (1 = most accurate) within each scenario",
    x = "Generative scenario", y = NULL
  ) +
  theme(panel.grid = element_blank())
save_fig(p3, "03_model_ranking_heatmap", subdir = "tree_accuracy", width = 6, height = 7)

# plot 4: violin + jitter for full distributional shape
p4 <- ggplot(rep_df, aes(x = modelID, y = cid, color = scenario)) +
  geom_violin(aes(fill = scenario), alpha = 0.15, position = position_dodge(0.8), linewidth = 0.4) +
  geom_jitter(size = 0.6, alpha = 0.4, position = position_jitterdodge(dodge.width = 0.8, jitter.width = 0.15)) +
  scale_color_manual(values = SCENARIO_COLORS, guide = "none") +
  scale_fill_manual(values = SCENARIO_COLORS, name = "Generative scenario") +
  coord_flip() +
  labs(
    title = "Full CID distribution per model (replicate-level detail)",
    subtitle = "Reveals bimodal failure modes hidden by boxplot summaries",
    x = NULL, y = "Clustering Information Distance (CID)"
  )
save_fig(p4, "04_cid_distribution_detail", subdir = "tree_accuracy", height = 7)

# plot 5: win-count - for every (scenario, grid cell), which model wins
sum_df <- safe_read_rds(PATHS$tree_accuracy_sum)

if (!is.null(sum_df)) {
  winners <- sum_df %>%
    filter(!is.na(median_cid)) %>%
    group_by(scenario, gridTag) %>%
    filter(median_cid == min(median_cid, na.rm = TRUE)) %>%
    ungroup() %>%
    label_models() %>%
    count(scenario, modelID, name = "n_wins")
  
  # keep every model in the plot even if it never wins, per scenario
  all_combos <- expand_grid(
    scenario = names(BASELINE_BY_SCENARIO),
    modelID  = factor(MODEL_LABELS[MODEL_IDS], levels = MODEL_LABELS[MODEL_IDS])
  )
  win_df <- all_combos %>%
    left_join(winners, by = c("scenario", "modelID")) %>%
    mutate(n_wins = replace_na(n_wins, 0L))
  
  p5 <- ggplot(win_df, aes(x = modelID, y = n_wins, fill = scenario)) +
    geom_col(position = position_dodge(0.7), width = 0.6) +
    facet_wrap(~ scenario, scales = "free_x") +
    scale_fill_manual(values = SCENARIO_COLORS, guide = "none") +
    coord_flip() +
    labs(
      title = "Which model wins each grid cell? (lowest median CID)",
      subtitle = "Count of grid cells where each model is the single most accurate, per scenario",
      x = NULL, y = "Number of grid cells won"
    )
  save_fig(p5, "05_grid_cell_win_counts", subdir = "tree_accuracy", width = 10, height = 7)
} else {
  message("tree_accuracy_summary.rds not found - skipping grid-cell win-count plot 5.")
}

message("\ntree_accuracy_plots.R complete - figures written to ", PATHS$fig_dir)