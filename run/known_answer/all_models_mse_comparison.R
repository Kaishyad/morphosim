# Full MSE comparison across all twelve models, corrected for the mean-of-
# ratios artefact discovered when only Model 1/2/8 were checked (relative
# MSE = MSE/true^2 shrinks sharply as true tree_length grows, so a single
# pooled average overweights short-tree-length cells). This script reports
# BOTH the naive pooled figure (for comparability with earlier work) AND
# two artefact-resistant alternatives, for every model:
#   (a) MSE broken down by tree_length (lets you see the real, un-confounded
#       comparison directly, the same way the Model 2 diagnosis worked)
#   (b) a "ratio of sums" statistic (sum of squared error / sum of true^2)
#       instead of a "mean of ratios" -- much less sensitive to a few
#       small-denominator cells dominating the average
#
# Writes CSVs to results/known_answer/ -- upload these back for analysis.

source("R/core/_setup.R")
source("run/shared/config_theme.R")
library(dplyr)
library(readr)

ka <- readRDS(PATHS$known_answer) %>%
  as_tibble() %>%
  mutate(
    true_rate_loss   = 1 / gain_loss,
    rel_mse_tree_len  = mse_tree_len  / (tree_length^2),
    rel_mse_rate_loss = mse_rate_loss / (true_rate_loss^2)
  )

out_dir <- file.path(PATHS$results_dir, "known_answer")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# --- 1. Naive pooled figure, all 12 models (same computation as before,
#         now for every model rather than just 1/2/8 -- kept for continuity
#         but flagged as artefact-prone; see (2) and (3) below for the
#         corrected versions) ---
naive_pooled <- ka %>%
  group_by(modelID, scenario) %>%
  summarise(
    mean_mse_tree_len      = mean(mse_tree_len, na.rm = TRUE),
    mean_rel_mse_tree_len  = mean(rel_mse_tree_len, na.rm = TRUE),
    mean_mse_rate_loss     = mean(mse_rate_loss, na.rm = TRUE),
    mean_rel_mse_rate_loss = mean(rel_mse_rate_loss, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(scenario, mean_rel_mse_tree_len)

write_csv(naive_pooled, file.path(out_dir, "mse_naive_pooled_all_models.csv"))

# --- 2. Artefact-resistant: MSE broken down by tree_length, all 12 models ---
by_treelength <- ka %>%
  group_by(modelID, scenario, tree_length) %>%
  summarise(mean_mse_tree_len     = mean(mse_tree_len, na.rm = TRUE),
            mean_rel_mse_tree_len = mean(rel_mse_tree_len, na.rm = TRUE),
            n = n(), .groups = "drop") %>%
  arrange(scenario, tree_length, mean_rel_mse_tree_len)

write_csv(by_treelength, file.path(out_dir, "mse_tree_len_by_model_treelength.csv"))

# --- 3. Artefact-resistant: MSE broken down by gain_loss ratio, all models
#         with an asymmetric rate matrix (only these estimate rate_loss) ---
by_gainloss <- ka %>%
  filter(!is.na(mse_rate_loss)) %>%
  group_by(modelID, scenario, gain_loss) %>%
  summarise(mean_mse_rate_loss     = mean(mse_rate_loss, na.rm = TRUE),
            mean_rel_mse_rate_loss = mean(rel_mse_rate_loss, na.rm = TRUE),
            n = n(), .groups = "drop") %>%
  arrange(scenario, gain_loss, mean_rel_mse_rate_loss)

write_csv(by_gainloss, file.path(out_dir, "mse_rate_loss_by_model_gainloss.csv"))

# --- 4. Ratio-of-sums summary: one robust number per model, all 12 ---
ratio_of_sums <- ka %>%
  group_by(modelID, scenario) %>%
  summarise(
    ros_rel_mse_tree_len  = sum(mse_tree_len, na.rm = TRUE) / sum(tree_length^2, na.rm = TRUE),
    ros_rel_mse_rate_loss = sum(mse_rate_loss, na.rm = TRUE) / sum(true_rate_loss^2, na.rm = TRUE),
    n_tree_len  = sum(!is.na(mse_tree_len)),
    n_rate_loss = sum(!is.na(mse_rate_loss)),
    .groups = "drop"
  ) %>%
  arrange(scenario, ros_rel_mse_tree_len)

write_csv(ratio_of_sums, file.path(out_dir, "mse_ratio_of_sums_all_models.csv"))

# --- 5. Side-by-side: naive mean-of-ratios vs ratio-of-sums, to show how
#         much the two methods disagree per model (large disagreement =
#         that model's naive figure was heavily artefact-driven) ---
comparison <- naive_pooled %>%
  select(modelID, scenario, mean_rel_mse_tree_len) %>%
  inner_join(ratio_of_sums %>% select(modelID, scenario, ros_rel_mse_tree_len),
             by = c("modelID","scenario")) %>%
  mutate(pct_difference = 100 * (mean_rel_mse_tree_len - ros_rel_mse_tree_len) / ros_rel_mse_tree_len) %>%
  arrange(scenario, desc(abs(pct_difference)))

write_csv(comparison, file.path(out_dir, "mse_method_comparison_all_models.csv"))

cat("Wrote 5 CSVs to", out_dir, "\n")
cat("- mse_naive_pooled_all_models.csv (artefact-prone, kept for reference)\n")
cat("- mse_tree_len_by_model_treelength.csv (artefact-resistant, use this for tree-length claims)\n")
cat("- mse_rate_loss_by_model_gainloss.csv (artefact-resistant, use this for rate-loss claims)\n")
cat("- mse_ratio_of_sums_all_models.csv (single robust number per model)\n")
cat("- mse_method_comparison_all_models.csv (shows which models' naive figures were most inflated)\n")
