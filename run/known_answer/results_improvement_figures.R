# Three additions to strengthen the Results chapter:
#   A) Coverage vs relative-MSE scatter -- makes the "Model 8/10 look fine on
#      coverage but are actually imprecise" finding visible at a glance,
#      currently only described in prose (Results, Parameter Recovery).
#   B) Tree-ESS vs continuous-parameter ESS scatter -- makes the three
#      distinct convergence failure modes (Table 1) visible as three
#      separate regions of one plot, rather than a table alone.
#   C) A clean threshold-summary table -- turns the dense threshold prose
#      into a scannable CSV/table instead of a paragraph of numbers.

source("R/core/_setup.R")
source("run/shared/config_theme.R")
library(dplyr)
library(ggplot2)
library(readr)
library(tidyr)

model_labels <- c(model1="M1",model2="M2",model3="M3",model4="M4",model5="M5",
                   model6="M6",model7="M7",model8="M8 (NT)",model9="M9",
                   model10="M10",model11="M11",model12="M12")

# ============================================================
# A) Coverage vs relative-MSE scatter, NT tree length, all 12 models
# ============================================================
cgr <- readRDS(PATHS$cgr_coverage)
ka  <- readRDS(PATHS$known_answer) %>% as_tibble()

coverage_nt <- cgr %>%
  filter(scenario == "nt", parameter == "tree_length") %>%
  group_by(modelID) %>%
  summarise(coverage_rate = mean(coverage_rate, na.rm = TRUE), .groups = "drop")

rel_mse_nt <- ka %>%
  filter(scenario == "nt") %>%
  group_by(modelID) %>%
  summarise(rel_mse = sum(mse_tree_len, na.rm = TRUE) / sum(tree_length^2, na.rm = TRUE),
            .groups = "drop")

plotA_df <- coverage_nt %>%
  inner_join(rel_mse_nt, by = "modelID") %>%
  mutate(model_label = model_labels[modelID])

pA <- ggplot(plotA_df, aes(x = coverage_rate, y = rel_mse)) +
  geom_point(size = 3, colour = "#C44E52") +
  ggrepel::geom_text_repel(aes(label = model_label), size = 3.5, seed = 1) +
  geom_vline(xintercept = 0.95, linetype = "dashed", colour = "grey50") +
  annotate("text", x = 0.95, y = max(plotA_df$rel_mse), label = "nominal 95% coverage",
           angle = 90, vjust = -0.5, size = 3, colour = "grey50") +
  labs(
    title = "Coverage rate vs relative error, tree length (NT-generated data)",
    subtitle = "Models in the upper-left (e.g. M8, M10) achieve moderate coverage via wide,\nimprecise intervals rather than accurate ones -- coverage alone hides this",
    x = "Observed coverage (95% CI target)",
    y = "Relative MSE (ratio-of-sums; lower = more precise)"
  ) +
  theme_minimal(base_size = 12)

ggsave(file.path(PATHS$fig_dir, "cgr", "12_coverage_vs_precision.png"),
       pA, width = 8, height = 6, dpi = 300)

# ============================================================
# B) Tree-ESS vs continuous-parameter ESS scatter, all 12 models
# ============================================================
conv <- readRDS(PATHS$convergence)

ess_summary <- conv %>%
  group_by(scenario, modelID) %>%
  summarise(median_ess_min = median(ess_min, na.rm = TRUE),
            median_tree_ess = median(tree_ess, na.rm = TRUE),
            .groups = "drop") %>%
  mutate(model_label = model_labels[modelID],
         failure_type = case_when(
           modelID == "model11" ~ "Tree-topology mixing weak\n(M11)",
           modelID %in% c("model7","model9") ~ "Continuous-parameter mixing weak\n(M7, M9)",
           modelID == "model12" ~ "Continuous-parameter mixing weak,\nworsens with tree length (M12)",
           TRUE ~ "No notable weakness"
         ))

pB <- ggplot(ess_summary, aes(x = median_ess_min, y = median_tree_ess, colour = failure_type)) +
  geom_point(size = 3) +
  ggrepel::geom_text_repel(aes(label = model_label), size = 3.5, seed = 1, show.legend = FALSE) +
  facet_wrap(~scenario, labeller = labeller(scenario = c(mk="Mk-generated", nt="NT-generated"))) +
  scale_colour_manual(values = c(
    "Tree-topology mixing weak\n(M11)" = "#C44E52",
    "Continuous-parameter mixing weak\n(M7, M9)" = "#DD8452",
    "Continuous-parameter mixing weak,\nworsens with tree length (M12)" = "#8172B2",
    "No notable weakness" = "#4C72B0"
  )) +
  labs(
    title = "Three distinct convergence failure modes across the twelve models",
    subtitle = "Position shows which ESS diagnostic is comparatively weak for each model",
    x = "Median continuous-parameter ESS", y = "Median tree-topology ESS", colour = NULL
  ) +
  theme_minimal(base_size = 12) +
  theme(legend.position = "bottom")

ggsave(file.path(PATHS$fig_dir, "convergence", "13_ess_failure_modes.png"),
       pB, width = 10, height = 6, dpi = 300)

# ============================================================
# C) Clean threshold summary table (CSV, easy to turn into a LaTeX table)
# ============================================================
thresh_mk <- readRDS(PATHS$threshold_mk) %>% mutate(scenario = "mk")
thresh_nt <- readRDS(PATHS$threshold_nt) %>% mutate(scenario = "nt")

threshold_table <- bind_rows(thresh_mk, thresh_nt) %>%
  filter(!is.na(threshold)) %>%
  mutate(model_label = model_labels[modelID]) %>%
  select(scenario, model_label, predictor, threshold, direction, stable) %>%
  arrange(scenario, predictor, threshold)

write_csv(threshold_table, file.path(PATHS$results_dir, "gam_threshold", "threshold_summary_table_clean.csv"))

cat("Saved:\n")
cat("- figures/cgr/12_coverage_vs_precision.png\n")
cat("- figures/convergence/13_ess_failure_modes.png\n")
cat("- results/gam_threshold/threshold_summary_table_clean.csv\n")
