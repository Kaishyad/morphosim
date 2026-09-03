# Four redesigned figures, each built to carry one section on its own
# rather than requiring the reader to cross-reference a dense table or
# parse an overloaded scatter plot.

source("R/core/_setup.R")
source("run/shared/config_theme.R")
library(dplyr)
library(ggplot2)
library(readr)
library(tidyr)
library(forcats)

model_labels <- c(model1="M1",model2="M2",model3="M3",model4="M4",model5="M5",
                   model6="M6",model7="M7",model8="M8",model9="M9",
                   model10="M10",model11="M11",model12="M12")

theme_clean <- theme_minimal(base_size = 13) +
  theme(panel.grid.minor = element_blank(),
        plot.title = element_text(face = "bold"),
        plot.subtitle = element_text(colour = "grey35", size = 10.5))

# ============================================================
# A) Relative MSE (tree length), NT-generated data, all 12 models
#    Horizontal bar, log scale, sorted best to worst, one clear number
#    per model instead of a table.
# ============================================================
ka <- readRDS(PATHS$known_answer) %>% as_tibble()

rel_mse <- ka %>%
  filter(scenario == "nt") %>%
  group_by(modelID) %>%
  summarise(rel_mse = sum(mse_tree_len, na.rm = TRUE) / sum(tree_length^2, na.rm = TRUE),
            .groups = "drop") %>%
  mutate(model_label = model_labels[modelID],
         highlight = case_when(modelID == "model11" ~ "best",
                                modelID == "model2"  ~ "worst",
                                TRUE ~ "other"))

pA <- ggplot(rel_mse, aes(x = fct_reorder(model_label, rel_mse), y = rel_mse, fill = highlight)) +
  geom_col(width = 0.7) +
  geom_text(aes(label = sprintf("%.3f", rel_mse)), hjust = -0.15, size = 3.4) +
  coord_flip() +
  scale_y_log10(expand = expansion(mult = c(0, 0.18))) +
  scale_fill_manual(values = c(best = "#4C956C", worst = "#C1121F", other = "#8C8C8C"),
                     guide = "none") +
  labs(
    title = "Relative tree-length error by model (NT-generated data)",
    subtitle = "Ratio-of-sums RMSE normalised by true tree length, log scale. Lower is more precise.",
    x = NULL, y = "Relative MSE (log scale)"
  ) +
  theme_clean

ggsave(file.path(PATHS$fig_dir, "known_answer", "05_relative_mse_tree_length.png"),
       pA, width = 8, height = 6, dpi = 300)

# ============================================================
# B) Threshold summary heatmap: model x predictor, both scenarios
#    Replaces a paragraph of prose numbers with one compact grid.
#    Blank/grey cell = no detectable crossing within the tested range.
# ============================================================
thresh_mk <- readRDS(PATHS$threshold_mk) %>% mutate(scenario = "Mk-generated")
thresh_nt <- readRDS(PATHS$threshold_nt) %>% mutate(scenario = "NT-generated")

thresh_all <- bind_rows(thresh_mk, thresh_nt) %>%
  mutate(model_label = factor(model_labels[modelID], levels = rev(model_labels)),
         predictor_label = recode(predictor,
                                   tree_length = "Tree length",
                                   rate_ratio = "Gain:loss ratio",
                                   chars_per_taxon = "Chars per taxon"),
         has_threshold = !is.na(threshold),
         label = ifelse(has_threshold, sprintf("%.2f", threshold), ""))

pB <- ggplot(thresh_all, aes(x = predictor_label, y = model_label, fill = has_threshold)) +
  geom_tile(colour = "white", linewidth = 0.6) +
  geom_text(aes(label = label), size = 3.3, colour = "white", fontface = "bold") +
  facet_wrap(~scenario) +
  scale_fill_manual(values = c(`TRUE` = "#2A6F97", `FALSE` = "#E0E0E0"), guide = "none") +
  labs(
    title = "Where a detectable threshold exists, by model and predictor",
    subtitle = "Coloured cells show the crossing value; grey cells found no sign change in the tested range",
    x = NULL, y = NULL
  ) +
  theme_clean +
  theme(panel.grid = element_blank(), axis.text.x = element_text(angle = 20, hjust = 1))

ggsave(file.path(PATHS$fig_dir, "gam_threshold", "14_threshold_heatmap.png"),
       pB, width = 9, height = 7, dpi = 300)

# ============================================================
# C) Parameter Recovery: clean coverage-rate bar chart, both scenarios
#    Replaces the coverage-vs-nominal scatter (confusing bubble sizes
#    and overlapping labels) with one unambiguous chart per scenario.
# ============================================================
cgr <- readRDS(PATHS$cgr_coverage)

coverage <- cgr %>%
  filter(parameter == "tree_length") %>%
  group_by(scenario, modelID) %>%
  summarise(coverage_rate = mean(coverage_rate, na.rm = TRUE), .groups = "drop") %>%
  mutate(model_label = model_labels[modelID],
         scenario_label = recode(scenario, mk = "Mk-generated", nt = "NT-generated"))

pC <- ggplot(coverage, aes(x = fct_reorder(model_label, coverage_rate), y = coverage_rate)) +
  geom_col(fill = "#2A6F97", width = 0.7) +
  geom_hline(yintercept = 0.95, linetype = "dashed", colour = "#C1121F", linewidth = 0.6) +
  annotate("text", x = 1.5, y = 0.99, label = "95% nominal target",
           colour = "#C1121F", size = 3.2, hjust = 0) +
  coord_flip() +
  scale_y_continuous(labels = scales::percent, limits = c(0, 1)) +
  facet_wrap(~scenario_label) +
  labs(
    title = "Tree-length coverage by model",
    subtitle = "Proportion of 95% credible intervals containing the true tree length",
    x = NULL, y = "Observed coverage"
  ) +
  theme_clean

ggsave(file.path(PATHS$fig_dir, "cgr", "06_coverage_by_model.png"),
       pC, width = 10, height = 6, dpi = 300)

# Companion panel: relative MSE alongside coverage, same model order,
# so the coverage-vs-precision disconnect (Model 8, Model 10) is visible
# by comparing the two panels directly rather than reading a scatter.
rel_mse_both <- ka %>%
  group_by(scenario, modelID) %>%
  summarise(rel_mse = sum(mse_tree_len, na.rm = TRUE) / sum(tree_length^2, na.rm = TRUE),
            .groups = "drop") %>%
  mutate(model_label = model_labels[modelID],
         scenario_label = recode(scenario, mk = "Mk-generated", nt = "NT-generated"))

pC2 <- ggplot(rel_mse_both, aes(x = fct_reorder(model_label, rel_mse), y = rel_mse)) +
  geom_col(fill = "#8C8C8C", width = 0.7) +
  coord_flip() +
  scale_y_log10() +
  facet_wrap(~scenario_label) +
  labs(
    title = "Relative tree-length error by model",
    subtitle = "Same models as above -- compare against coverage directly; a model can have\nreasonable coverage while still being imprecise (e.g. wide intervals)",
    x = NULL, y = "Relative MSE (log scale)"
  ) +
  theme_clean

ggsave(file.path(PATHS$fig_dir, "cgr", "07_relative_mse_by_model_both_scenarios.png"),
       pC2, width = 10, height = 6, dpi = 300)

# ============================================================
# D) Omnibus Result: compact ranking plot, median CID with IQR,
#    ordered by rank, emphasising the narrow spread the Friedman test
#    sits on top of. Complements (does not replace) the full boxplot.
# ============================================================
tas <- readRDS(PATHS$tree_accuracy_sum)

ranking <- tas %>%
  group_by(scenario, modelID) %>%
  summarise(median_cid = median(median_cid, na.rm = TRUE),
            q1 = quantile(median_cid, 0.25, na.rm = TRUE),
            q3 = quantile(median_cid, 0.75, na.rm = TRUE),
            .groups = "drop") %>%
  mutate(model_label = model_labels[modelID],
         scenario_label = recode(scenario, mk = "Mk-generated", nt = "NT-generated"))

pD <- ggplot(ranking, aes(x = fct_reorder(model_label, -median_cid), y = median_cid)) +
  geom_pointrange(aes(ymin = q1, ymax = q3), colour = "#2A6F97", size = 0.6, linewidth = 0.8) +
  coord_flip() +
  facet_wrap(~scenario_label, scales = "free_x") +
  labs(
    title = "Model ranking by median tree accuracy",
    subtitle = "Point = median CID, bar = interquartile range across grid cells.\nDifferences are statistically decisive (Friedman p < 0.001) despite the narrow spread shown here.",
    x = NULL, y = "Clustering Information Distance (lower is more accurate)"
  ) +
  theme_clean

ggsave(file.path(PATHS$fig_dir, "tree_accuracy", "02_omnibus_ranking.png"),
       pD, width = 10, height = 6, dpi = 300)

cat("Saved:\n")
cat("- figures/known_answer/05_relative_mse_tree_length.png\n")
cat("- figures/gam_threshold/14_threshold_heatmap.png\n")
cat("- figures/cgr/06_coverage_by_model.png\n")
cat("- figures/cgr/07_relative_mse_by_model_both_scenarios.png\n")
cat("- figures/tree_accuracy/02_omnibus_ranking.png\n")
