# convergence_diagnostics.R

source("run/shared/config_theme.R")

df <- safe_read_rds(PATHS$convergence)
if (is.null(df)) quit(save = "no")

df <- df %>% label_models()

# PLOT 1: Convergence pass-rate heatmap (the "can we trust this" gate)
pass_df <- df %>%
  group_by(modelID, scenario) %>%
  summarise(pass_rate = mean(as.numeric(pass), na.rm = TRUE), n = n(), .groups = "drop")

p1 <- ggplot(pass_df, aes(x = scenario, y = fct_rev(modelID), fill = pass_rate)) +
  geom_tile(color = "white", linewidth = 0.8) +
  geom_text(aes(label = scales::percent(pass_rate, accuracy = 1)), size = 3.3) +
  scale_fill_gradient2(low = "#B2182B", mid = "#FEE08B", high = "#1A9850",
                        midpoint = 0.5, limits = c(0, 1), name = "Convergence\npass rate") +
  labs(
    title = "MCMC convergence pass rate by model",
    subtitle = "Proportion of runs meeting ESS / R-hat / ASDSF thresholds",
    x = "Generative scenario", y = NULL
  ) +
  theme(panel.grid = element_blank())
save_fig(p1, "06_convergence_pass_rate_heatmap", subdir = "convergence", width = 6, height = 7)

# PLOT 2: R-hat distribution with the pipeline's own threshold line
p2 <- ggplot(df, aes(x = modelID, y = rhat_max, color = scenario)) +
  geom_hline(yintercept = RHAT_MAX, linetype = "dashed", color = "grey40") +
  geom_jitter(width = 0.15, alpha = 0.35, size = 0.8) +
  stat_summary(fun = median, geom = "point", size = 2.5, shape = 18,
               position = position_dodge(0.6)) +
  scale_color_manual(values = SCENARIO_COLORS, name = "Generative scenario") +
  coord_flip() +
  labs(
    title = "Rank-normalised R-hat (max over parameters) by model",
    subtitle = paste0("Dashed line = pipeline convergence threshold (RHAT_MAX = ", RHAT_MAX, ")"),
    x = NULL, y = "R-hat (max)"
  )
save_fig(p2, "07_rhat_by_model", subdir = "convergence", height = 7)

# PLOT 3: ESS distribution (log scale, pipeline's ESS_MIN reference)
p3 <- ggplot(df, aes(x = modelID, y = ess_min, color = scenario)) +
  geom_hline(yintercept = ESS_MIN, linetype = "dashed", color = "grey40") +
  geom_jitter(width = 0.15, alpha = 0.35, size = 0.8) +
  stat_summary(fun = median, geom = "point", size = 2.5, shape = 18,
               position = position_dodge(0.6)) +
  scale_y_log10(labels = label_comma()) +
  scale_color_manual(values = SCENARIO_COLORS, name = "Generative scenario") +
  coord_flip() +
  labs(
    title = "Effective sample size (min over parameters) by model",
    subtitle = paste0("Dashed line = pipeline minimum ESS threshold (ESS_MIN = ", ESS_MIN, ")"),
    x = NULL, y = "ESS min (log scale)"
  )
save_fig(p3, "08_ess_by_model", subdir = "convergence", height = 7)

# PLOT 4: ASDSF distribution (MC^3 chain agreement)
p4 <- ggplot(df, aes(x = modelID, y = asdsf, color = scenario)) +
  geom_hline(yintercept = ASDSF_MAX, linetype = "dashed", color = "grey40") +
  geom_jitter(width = 0.15, alpha = 0.35, size = 0.8) +
  stat_summary(fun = median, geom = "point", size = 2.5, shape = 18,
               position = position_dodge(0.6)) +
  scale_color_manual(values = SCENARIO_COLORS, name = "Generative scenario") +
  coord_flip() +
  labs(
    title = "Average SD of split frequencies (ASDSF) by model",
    subtitle = paste0("Dashed line = pipeline convergence threshold (ASDSF_MAX = ", ASDSF_MAX, ")"),
    x = NULL, y = "ASDSF"
  )
save_fig(p4, "09_asdsf_by_model", subdir = "convergence", height = 7)

# PLOT 5: Tree ESS vs scalar ESS -- move-schedule diagnostic already
has_tree_ess <- df %>% filter(!is.na(tree_ess), !is.na(ess_min))
if (nrow(has_tree_ess) > 0L) {
  p5 <- ggplot(has_tree_ess, aes(x = ess_min, y = tree_ess, color = scenario)) +
    geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "grey40") +
    geom_point(alpha = 0.4, size = 1) +
    scale_x_log10(labels = label_comma()) +
    scale_y_log10(labels = label_comma()) +
    scale_color_manual(values = SCENARIO_COLORS, name = "Generative scenario") +
    labs(
      title = "Tree ESS vs scalar-parameter ESS",
      subtitle = "Points below the dashed line: tree mixing lags scalar-parameter mixing (move schedule check)",
      x = "ESS min (scalar parameters, log scale)", y = "Tree ESS (log scale)"
    )
  save_fig(p5, "10_tree_ess_vs_scalar_ess", subdir = "convergence", height = 5.5)
}

# PLOT 6: Does poor convergence predict poor tree accuracy?
acc <- safe_read_rds(PATHS$tree_accuracy_rep)
if (!is.null(acc)) {
  acc <- acc %>% rename(cid = median_cid)

  joined <- df %>%
    inner_join(acc, by = c("scenario", "gridTag", "repID", "modelID"))

  p6 <- ggplot(joined, aes(x = rhat_max, y = cid, color = scenario)) +
    geom_point(alpha = 0.4, size = 1) +
    geom_smooth(method = "lm", se = TRUE, linewidth = 0.7) +
    scale_color_manual(values = SCENARIO_COLORS, name = "Generative scenario") +
    labs(
      title = "Does poor convergence predict poor tree accuracy?",
      subtitle = "Each point = one (scenario, grid cell, replicate, model); trend line per scenario",
      x = "R-hat (max)", y = "CID"
    )
  save_fig(p6, "11_convergence_vs_accuracy", subdir = "convergence", height = 5.5)
}

message("\nconvergence_diagnostics.R complete -- figures written to ", PATHS$fig_dir)
