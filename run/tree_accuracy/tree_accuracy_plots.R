source("run/shared/config_theme.R")

rep_df <- safe_read_rds(PATHS$tree_accuracy_rep)
if (is.null(rep_df)) quit(save = "no")

rep_df <- rep_df %>%
  filter(!is.na(median_cid)) %>%
  rename(cid = median_cid) %>%
  label_models()

# PLOT 1: CID distribution by model, faceted by scenario
p1 <- ggplot(rep_df, aes(x = modelID, y = cid, fill = scenario)) +
  geom_boxplot(outlier.alpha = 0.3, width = 0.6, position = position_dodge(0.7)) +
  scale_fill_manual(values = SCENARIO_COLORS, name = "Generative scenario") +
  coord_flip() +
  labs(
    title = "Tree accuracy (Clustering Information Distance) by model",
    subtitle = "Lower CID = more accurate topology recovery. One row per (scenario, grid cell, replicate).",
    x = NULL, y = "Clustering Information Distance (CID)"
  )
save_fig(p1, "01_cid_by_model_scenario", subdir = "tree_accuracy", height = 7)

# PLOT 2: Delta-CID relative to the scenario-appropriate baseline
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

# PLOT 3: Model ranking heatmap - mean CID, model x scenario
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

# PLOT 4: Violin + jitter for full distributional shape
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

# PLOT 5: Win-count - for every (scenario, grid cell) which model
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
