# 10_known_answer_analysis.R
#
# Answers the "Further Questions" set for known_answer_summary.rds:
# model ranking, MK vs NT comparison, gridTag failure analysis, parameter
# main effects, MSE-vs-coverage relationship, and overall robustness.
#
# Outputs go in their own subfolders (new convention -- other viz scripts
# still write flat into results_dir/fig_dir; this one groups everything
# under a known_answer/ subfolder in each so it's easy to find):
#   the-matrix/results/known_answer/*.csv
#   the-matrix/figures/known_answer/*.png, *.pdf
#
# Coverage threshold used throughout: 0.95 (per the "Further Questions" spec).
# Note: if cov_rate_loss / mse_rate_loss are NA for every row (a known
# stale-data issue as of 2026-07-18), this script still runs and reports
# rate-based results as NA / all-missing rather than failing -- rerun
# known_answer + merge once that's fixed to get real rate-loss numbers.

source("viz/00_config_theme.R")

COVERAGE_THRESHOLD <- 0.95

# --- Subfolder setup (local to this script) --------------------------------
RESULTS_KA_DIR <- file.path(PATHS$results_dir, "known_answer")
FIG_KA_DIR     <- file.path(PATHS$fig_dir, "known_answer")
dir.create(RESULTS_KA_DIR, showWarnings = FALSE, recursive = TRUE)
dir.create(FIG_KA_DIR, showWarnings = FALSE, recursive = TRUE)

write_table_ka <- function(df, name) {
  path <- file.path(RESULTS_KA_DIR, paste0(name, ".csv"))
  readr::write_csv(df, path)
  message("Saved table: ", name, " -> ", path)
}

save_fig_ka <- function(plot, name, width = 8, height = 5.5, dpi = 300,
                        formats = c("png", "pdf")) {
  for (fmt in formats) {
    ggsave(
      filename = file.path(FIG_KA_DIR, paste0(name, ".", fmt)),
      plot = plot, width = width, height = height, dpi = dpi, bg = "white"
    )
  }
  message("Saved figure: ", name, " (", paste(formats, collapse = ", "), ") -> ", FIG_KA_DIR)
}

# --- Load data ---------------------------------------------------------
ka <- safe_read_rds(PATHS$known_answer)
if (is.null(ka)) {
  message("known_answer_summary.rds not found -- nothing to analyze. Stopping.")
  quit(save = "no")
}

if (all(is.na(ka$cov_rate_loss)) && all(is.na(ka$mse_rate_loss))) {
  warning("cov_rate_loss / mse_rate_loss are NA for every row -- rate-based ",
          "results below will be all-NA. This matches a known stale-data ",
          "issue; rerun known_answer + merge_known_answer for real numbers.")
}

ka <- ka %>% label_models()

# =========================================================================
# TABLE 1 -- Model ranking (avg coverage, avg MSE, both parameters)
# =========================================================================
table1_model_ranking <- ka %>%
  group_by(modelID, modelID_label) %>%
  summarise(
    mean_cov_tree_len  = mean(cov_tree_len,  na.rm = TRUE),
    mean_cov_rate_loss = mean(cov_rate_loss, na.rm = TRUE),
    mean_mse_tree_len  = mean(mse_tree_len,  na.rm = TRUE),
    mean_mse_rate_loss = mean(mse_rate_loss, na.rm = TRUE),
    n_cells            = n(),
    .groups = "drop"
  ) %>%
  arrange(desc(mean_cov_tree_len), mean_mse_tree_len)
write_table_ka(table1_model_ranking, "table1_model_ranking")

# =========================================================================
# TABLE 2 -- MK vs NT comparison per model
# (count + % of grid cells below threshold, per scenario, per model)
# =========================================================================
table2_mk_vs_nt <- ka %>%
  group_by(modelID, modelID_label, scenario) %>%
  summarise(
    n_cells       = n(),
    n_below_95    = sum(cov_tree_len < COVERAGE_THRESHOLD, na.rm = TRUE),
    pct_below_95  = round(100 * n_below_95 / n_cells, 1),
    mean_cov      = mean(cov_tree_len, na.rm = TRUE),
    mean_mse      = mean(mse_tree_len, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  pivot_wider(
    id_cols = c(modelID, modelID_label),
    names_from = scenario,
    values_from = c(n_below_95, pct_below_95, mean_cov, mean_mse)
  ) %>%
  mutate(
    failures_diff_nt_minus_mk = n_below_95_nt - n_below_95_mk
  ) %>%
  arrange(desc(failures_diff_nt_minus_mk))
write_table_ka(table2_mk_vs_nt, "table2_mk_vs_nt_comparison")

# =========================================================================
# TABLE 3 -- GridTag failure summary (coverage < threshold)
# =========================================================================
table3_gridtag_failures <- ka %>%
  filter(cov_tree_len < COVERAGE_THRESHOLD) %>%
  count(gridTag, tree_length, gain_loss, n_char, name = "n_failures") %>%
  arrange(desc(n_failures))
write_table_ka(table3_gridtag_failures, "table3_gridtag_failure_summary")

# =========================================================================
# TABLE 4 -- Average MSE summary (models ranked by tree-length MSE)
# =========================================================================
table4_avg_mse <- ka %>%
  group_by(modelID, modelID_label) %>%
  summarise(
    mean_mse_tree_len  = mean(mse_tree_len,  na.rm = TRUE),
    mean_mse_rate_loss = mean(mse_rate_loss, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(mean_mse_tree_len)
write_table_ka(table4_avg_mse, "table4_average_mse_summary")

# =========================================================================
# TABLE 5 -- Count table: grid cells below threshold, per model, both scenarios pooled
# =========================================================================
table5_count_below_threshold <- ka %>%
  group_by(modelID, modelID_label) %>%
  summarise(
    n_cells      = n(),
    n_below_95   = sum(cov_tree_len < COVERAGE_THRESHOLD, na.rm = TRUE),
    pct_below_95 = round(100 * n_below_95 / n_cells, 1),
    .groups = "drop"
  ) %>%
  arrange(desc(pct_below_95))
write_table_ka(table5_count_below_threshold, "table5_count_below_threshold_by_model")

# =========================================================================
# TABLE 6 -- Which models struggle within each scenario (below threshold, per scenario)
# =========================================================================
table6_scenario_model_failures <- ka %>%
  group_by(scenario, modelID, modelID_label) %>%
  summarise(
    n_cells    = n(),
    n_below_95 = sum(cov_tree_len < COVERAGE_THRESHOLD, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(scenario, desc(n_below_95))
write_table_ka(table6_scenario_model_failures, "table6_scenario_model_failures")

# =========================================================================
# TABLE 7 -- Scenario-level overall comparison (MK vs NT)
# =========================================================================
table7_scenario_overall <- ka %>%
  group_by(scenario) %>%
  summarise(
    mean_cov_tree_len = mean(cov_tree_len, na.rm = TRUE),
    mean_mse_tree_len = mean(mse_tree_len, na.rm = TRUE),
    n_below_95        = sum(cov_tree_len < COVERAGE_THRESHOLD, na.rm = TRUE),
    n_cells           = n(),
    pct_below_95      = round(100 * n_below_95 / n_cells, 1),
    .groups = "drop"
  ) %>%
  arrange(desc(mean_cov_tree_len))
write_table_ka(table7_scenario_overall, "table7_scenario_overall_comparison")

# =========================================================================
# TABLE 8 -- Which simulation parameter has the greatest impact
# (range of mean coverage / MSE across levels of each parameter, pooled
# across models -- bigger range = bigger impact on performance)
# =========================================================================
.ParamImpact <- function(param) {
  ka %>%
    group_by(.data[[param]]) %>%
    summarise(
      mean_cov = mean(cov_tree_len, na.rm = TRUE),
      mean_mse = mean(mse_tree_len, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    summarise(
      parameter    = param,
      cov_range    = max(mean_cov, na.rm = TRUE) - min(mean_cov, na.rm = TRUE),
      mse_range    = max(mean_mse, na.rm = TRUE) - min(mean_mse, na.rm = TRUE),
      n_levels     = n()
    )
}
table8_parameter_impact <- bind_rows(
  .ParamImpact("tree_length"),
  .ParamImpact("gain_loss"),
  .ParamImpact("n_char")
) %>%
  arrange(desc(cov_range))
write_table_ka(table8_parameter_impact, "table8_parameter_impact_ranking")

# =========================================================================
# TABLE 9 -- Highest-MSE simulation conditions (sorted)
# =========================================================================
table9_highest_mse_conditions <- ka %>%
  group_by(gridTag, tree_length, gain_loss, n_char) %>%
  summarise(mean_mse_tree_len = mean(mse_tree_len, na.rm = TRUE), .groups = "drop") %>%
  arrange(desc(mean_mse_tree_len))
write_table_ka(table9_highest_mse_conditions, "table9_highest_mse_conditions")

# =========================================================================
# TABLE 10 -- Robustness summary (best models across ALL conditions)
# =========================================================================
table10_robustness <- ka %>%
  group_by(modelID, modelID_label) %>%
  summarise(
    mean_cov   = mean(cov_tree_len, na.rm = TRUE),
    mean_mse   = mean(mse_tree_len, na.rm = TRUE),
    sd_cov     = sd(cov_tree_len, na.rm = TRUE),
    n_failures = sum(cov_tree_len < COVERAGE_THRESHOLD, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(desc(mean_cov), mean_mse, sd_cov)
write_table_ka(table10_robustness, "table10_robustness_summary")

message("\nModel ranking (best-to-worst by coverage):")
print(table1_model_ranking %>% select(modelID, mean_cov_tree_len, mean_mse_tree_len))

# =========================================================================
# FIGURE 1 -- Coverage vs Tree Length
# =========================================================================
fig1_df <- ka %>%
  group_by(modelID_label, tree_length) %>%
  summarise(mean_cov = mean(cov_tree_len, na.rm = TRUE), .groups = "drop")

model_colors <- setNames(model_palette(length(unique(fig1_df$modelID_label))),
                         levels(fig1_df$modelID_label))

p1 <- ggplot(fig1_df, aes(x = tree_length, y = mean_cov, color = modelID_label, group = modelID_label)) +
  geom_hline(yintercept = COVERAGE_THRESHOLD, linetype = "dashed", color = "grey50") +
  geom_line(linewidth = 0.9, alpha = 0.85) +
  geom_point(size = 1.8) +
  scale_color_manual(values = model_colors, name = "Model") +
  labs(
    title = "Coverage vs tree length",
    subtitle = paste0("Dashed line = ", COVERAGE_THRESHOLD, " nominal coverage threshold"),
    x = "Tree length", y = "Mean coverage (tree length parameter)"
  )
save_fig_ka(p1, "01_coverage_vs_tree_length", width = 10, height = 6)

# =========================================================================
# FIGURE 2 -- MSE vs Tree Length
# =========================================================================
fig2_df <- ka %>%
  group_by(modelID_label, tree_length) %>%
  summarise(mean_mse = mean(mse_tree_len, na.rm = TRUE), .groups = "drop")

p2 <- ggplot(fig2_df, aes(x = tree_length, y = mean_mse, color = modelID_label, group = modelID_label)) +
  geom_line(linewidth = 0.9, alpha = 0.85) +
  geom_point(size = 1.8) +
  scale_color_manual(values = model_colors, name = "Model") +
  labs(
    title = "MSE vs tree length",
    subtitle = "Mean squared error, tree-length parameter (lower = better recovery)",
    x = "Tree length", y = "Mean MSE (tree length parameter)"
  )
save_fig_ka(p2, "02_mse_vs_tree_length", width = 10, height = 6)

# =========================================================================
# FIGURE 3 -- Coverage vs MSE (scatter, per grid cell per model)
# =========================================================================
p3 <- ggplot(ka, aes(x = mse_tree_len, y = cov_tree_len, color = modelID_label)) +
  geom_hline(yintercept = COVERAGE_THRESHOLD, linetype = "dashed", color = "grey50") +
  geom_point(alpha = 0.6, size = 1.6) +
  scale_color_manual(values = model_colors, name = "Model") +
  labs(
    title = "Coverage vs MSE",
    subtitle = "Does higher estimation error correspond to poorer calibration?",
    x = "MSE (tree length)", y = "Coverage (tree length)"
  )
save_fig_ka(p3, "03_coverage_vs_mse_scatter", width = 9, height = 6.5)

# =========================================================================
# FIGURE 4 -- Scenario comparison (MK vs NT), bar chart
# =========================================================================
p4 <- ggplot(table7_scenario_overall, aes(x = scenario, y = mean_cov_tree_len, fill = scenario)) +
  geom_col(width = 0.6) +
  geom_hline(yintercept = COVERAGE_THRESHOLD, linetype = "dashed", color = "grey50") +
  scale_fill_manual(values = SCENARIO_COLORS, guide = "none") +
  labs(
    title = "Overall coverage: MK vs NT",
    x = NULL, y = "Mean coverage (tree length)"
  )
save_fig_ka(p4, "04_scenario_comparison_bar", width = 6, height = 5.5)

message("\nAll known-answer analysis tables and figures written to:")
message("  Tables:  ", RESULTS_KA_DIR)
message("  Figures: ", FIG_KA_DIR)
