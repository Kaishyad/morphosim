## ============================================================
## 05_summary_dashboard.R
## One-page combined figure: the single image you'd put in a
## presentation or the top of the results chapter.
##
## Run:  Rscript viz/05_summary_dashboard.R
## Requires: tree_accuracy_per_rep + convergence_summary (+ tree_accuracy_summary
## for the win-count panel). Also requires 'patchwork':
## install.packages("patchwork")
## ============================================================

source("viz/00_config_theme.R")
suppressPackageStartupMessages(library(patchwork))

acc  <- safe_read_rds(PATHS$tree_accuracy_rep)
conv <- safe_read_rds(PATHS$convergence)

if (is.null(acc) || is.null(conv)) {
  message("Need both tree_accuracy_per_rep.rds and convergence_summary.rds for the dashboard -- skipping.")
  quit(save = "no")
}

acc  <- acc  %>% rename(cid = median_cid) %>% label_models()
conv <- conv %>% label_models()

# Panel A: CID by model/scenario (condensed)
panelA <- ggplot(acc, aes(x = modelID, y = cid, fill = scenario)) +
  geom_boxplot(outlier.alpha = 0.25, width = 0.6, position = position_dodge(0.7)) +
  scale_fill_manual(values = SCENARIO_COLORS, name = NULL) +
  coord_flip() +
  labs(title = "A. Tree accuracy (CID)", x = NULL, y = "CID") +
  theme(legend.position = "top")

# Panel B: convergence pass-rate heatmap (condensed)
pass_df <- conv %>%
  group_by(modelID, scenario) %>%
  summarise(pass_rate = mean(as.numeric(pass), na.rm = TRUE), .groups = "drop")

panelB <- ggplot(pass_df, aes(x = scenario, y = fct_rev(modelID), fill = pass_rate)) +
  geom_tile(color = "white") +
  geom_text(aes(label = scales::percent(pass_rate, accuracy = 1)), size = 2.8) +
  scale_fill_gradient2(low = "#B2182B", mid = "#FEE08B", high = "#1A9850",
                        midpoint = 0.5, limits = c(0, 1), name = NULL) +
  labs(title = "B. Convergence pass rate", x = NULL, y = NULL) +
  theme(panel.grid = element_blank(), legend.position = "top")

# Panel C: model ranking summary (mean CID) -- absolute, no baseline
rank_df <- acc %>%
  group_by(modelID, scenario) %>%
  summarise(mean_cid = mean(cid), .groups = "drop")

panelC <- ggplot(rank_df, aes(x = fct_reorder(modelID, mean_cid, .fun = mean), y = mean_cid, fill = scenario)) +
  geom_col(position = position_dodge(0.7), width = 0.6) +
  scale_fill_manual(values = SCENARIO_COLORS, name = NULL) +
  coord_flip() +
  labs(title = "C. Mean accuracy ranking", x = NULL, y = "Mean CID") +
  theme(legend.position = "none")

# Panel D: grid-cell win counts -- who's best, and how often, with
# no baseline framing at all (complements the baseline-relative
# panels above so the dashboard doesn't only show baseline deltas).
sum_df <- safe_read_rds(PATHS$tree_accuracy_sum)

if (!is.null(sum_df)) {
  winners <- sum_df %>%
    filter(!is.na(median_cid)) %>%
    group_by(scenario, gridTag) %>%
    filter(median_cid == min(median_cid, na.rm = TRUE)) %>%
    ungroup() %>%
    label_models() %>%
    count(scenario, modelID, name = "n_wins")

  panelD <- ggplot(winners, aes(x = modelID, y = n_wins, fill = scenario)) +
    geom_col(position = position_dodge(0.7), width = 0.6) +
    scale_fill_manual(values = SCENARIO_COLORS, name = NULL) +
    coord_flip() +
    labs(title = "D. Grid cells won (lowest CID)", x = NULL, y = "Grid cells won") +
    theme(legend.position = "none")

  dashboard <- (panelA | panelB) / (panelC | panelD) +
    plot_annotation(
      title = "Model performance overview: MK vs NT generative scenarios",
      subtitle = "Tree accuracy, MCMC convergence, overall ranking, and grid-cell wins across the 12-model grid",
      theme = theme(plot.title = element_text(face = "bold", size = 15))
    )
} else {
  message("tree_accuracy_summary.rds not found -- dashboard will omit the grid-cell win panel.")
  dashboard <- (panelA | panelB) / panelC +
    plot_annotation(
      title = "Model performance overview: MK vs NT generative scenarios",
      subtitle = "Tree accuracy, MCMC convergence, and overall ranking across the 12-model grid",
      theme = theme(plot.title = element_text(face = "bold", size = 15))
    )
}

save_fig(dashboard, "00_summary_dashboard", width = 13, height = 10)

message("\n05_summary_dashboard.R complete -- dashboard written to ", PATHS$fig_dir)
