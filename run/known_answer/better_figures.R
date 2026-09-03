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
# ============================================================
# BETTER FIGURES
# Same results as existing analysis, redesigned visualisations
# ============================================================

source("R/core/_setup.R")
source("run/shared/config_theme.R")

suppressPackageStartupMessages({
  library(tidyverse)
  library(scales)
  library(forcats)
})

# ============================================================
# COLOUR PALETTE
# ============================================================

SCENARIO_COLORS <- c(
  mk = "#3B82A0",
  nt = "#D97941"
)

FAMILY_COLORS <- c(
  "Single-partition Mk" = "#4C78A8",
  "Two-partition"       = "#59A14F",
  "Rate variation"      = "#B279A2",
  "Extended"            = "#E15759"
)

MODEL_FAMILY <- c(
  model1  = "Single-partition Mk",
  model2  = "Single-partition Mk",
  model3  = "Single-partition Mk",
  model4  = "Two-partition",
  model5  = "Two-partition",
  model6  = "Two-partition",
  model7  = "Rate variation",
  model8  = "Rate variation",
  model9  = "Rate variation",
  model10 = "Rate variation",
  model11 = "Extended",
  model12 = "Extended"
)

MODEL_LABELS <- c(
  model1  = "M1",
  model2  = "M2",
  model3  = "M3",
  model4  = "M4",
  model5  = "M5",
  model6  = "M6",
  model7  = "M7",
  model8  = "M8",
  model9  = "M9",
  model10 = "M10",
  model11 = "M11",
  model12 = "M12"
)

# ============================================================
# THEME
# ============================================================

theme_matrix <- function(base_size = 12) {
  
  theme_minimal(base_size = base_size) +
    
    theme(
      text = element_text(colour = "#303030"),
      
      plot.title = element_text(
        face = "bold",
        size = rel(1.15),
        margin = margin(b = 5)
      ),
      
      plot.subtitle = element_text(
        colour = "#666666",
        size = rel(0.88),
        margin = margin(b = 10)
      ),
      
      plot.caption = element_text(
        colour = "#777777",
        size = rel(0.75)
      ),
      
      panel.grid.minor = element_blank(),
      
      panel.grid.major.x = element_line(
        colour = "#E5E5E5",
        linewidth = 0.3
      ),
      
      panel.grid.major.y = element_blank(),
      
      strip.text = element_text(
        face = "bold",
        size = rel(0.9)
      ),
      
      strip.background = element_rect(
        fill = "#F1F1F1",
        colour = NA
      ),
      
      legend.position = "bottom",
      
      legend.title = element_text(
        face = "bold",
        size = rel(0.85)
      ),
      
      axis.title = element_text(
        size = rel(0.9)
      ),
      
      axis.text = element_text(
        colour = "#404040"
      )
    )
}

theme_set(theme_matrix())

# ============================================================
# OUTPUT DIRECTORIES
# ============================================================

FIG_DIR <- PATHS$fig_dir

dir.create(file.path(FIG_DIR, "tree_accuracy"),
           recursive = TRUE, showWarnings = FALSE)

dir.create(file.path(FIG_DIR, "known_answer"),
           recursive = TRUE, showWarnings = FALSE)

dir.create(file.path(FIG_DIR, "cgr"),
           recursive = TRUE, showWarnings = FALSE)

dir.create(file.path(FIG_DIR, "gam_threshold"),
           recursive = TRUE, showWarnings = FALSE)

# ============================================================
# HELPER
# ============================================================

save_plot <- function(plot, subdir, filename,
                      width = 9, height = 6) {
  
  ggsave(
    file.path(FIG_DIR, subdir, filename),
    plot = plot,
    width = width,
    height = height,
    dpi = 300,
    bg = "white"
  )
  
  message(
    "Saved: ",
    file.path("figures", subdir, filename)
  )
}

# ============================================================
# LOAD DATA
# ============================================================

tas <- readRDS(PATHS$tree_accuracy_sum) %>%
  as_tibble()

ka <- readRDS(PATHS$known_answer) %>%
  as_tibble()

cgr <- readRDS(PATHS$cgr_coverage)

thresh_mk <- readRDS(PATHS$threshold_mk)
thresh_nt <- readRDS(PATHS$threshold_nt)

# ============================================================
# COMMON TREE ACCURACY SUMMARY
# ============================================================

accuracy <- tas %>%
  group_by(scenario, modelID) %>%
  summarise(
    median_cid = median(median_cid, na.rm = TRUE),
    q1 = quantile(median_cid, 0.25, na.rm = TRUE),
    q3 = quantile(median_cid, 0.75, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(
    model = MODEL_LABELS[modelID],
    family = MODEL_FAMILY[modelID],
    scenario_label = recode(
      scenario,
      mk = "Mk-generated",
      nt = "NT-generated"
    )
  )

# ============================================================
# 01. TREE ACCURACY — DOT + IQR
# ============================================================

p01 <- ggplot(
  accuracy,
  aes(
    x = median_cid,
    y = fct_reorder(model, median_cid),
    colour = scenario
  )
) +
  
  geom_errorbar(
    aes(
      xmin = q1,
      xmax = q3
    ),
    orientation = "y",
    height = 0.16,
    linewidth = 0.8
  ) +
  
  geom_point(size = 3.1) +
  
  facet_wrap(~scenario_label) +
  
  scale_colour_manual(
    values = SCENARIO_COLORS
  ) +
  
  labs(
    title = "Tree accuracy across models",
    subtitle = "Points show median CID and lines show the interquartile range",
    x = "Clustering Information Distance",
    y = NULL,
    colour = NULL
  )

save_plot(
  p01,
  "tree_accuracy",
  "03_accuracy_dotplot.png"
)

# ============================================================
# 02. TREE ACCURACY — HEATMAP BY CHARACTER COUNT
# ============================================================

acc_chars <- tas %>%
  group_by(
    scenario,
    modelID,
    n_char
  ) %>%
  summarise(
    cid = median(median_cid, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(
    model = factor(
      MODEL_LABELS[modelID],
      levels = paste0("M", 12:1)
    ),
    scenario_label = recode(
      scenario,
      mk = "Mk-generated",
      nt = "NT-generated"
    )
  )

p02 <- ggplot(
  acc_chars,
  aes(
    x = n_char,
    y = model,
    fill = cid
  )
) +
  
  geom_tile(
    colour = "white",
    linewidth = 0.5
  ) +
  
  scale_fill_viridis_c(
    option = "mako",
    direction = -1,
    name = "CID"
  ) +
  
  facet_wrap(~scenario_label) +
  
  labs(
    title = "Tree accuracy across character counts",
    subtitle = "Lower CID indicates greater topological accuracy",
    x = "Number of characters",
    y = NULL
  ) +
  
  theme(
    panel.grid = element_blank()
  )

save_plot(
  p02,
  "tree_accuracy",
  "04_accuracy_character_heatmap.png",
  width = 9,
  height = 7
)

# ============================================================
# 03. TREE ACCURACY — ACCURACY AGAINST CHARACTER COUNT
# ============================================================

p03 <- ggplot(
  acc_chars,
  aes(
    x = n_char,
    y = cid,
    group = modelID
  )
) +
  
  geom_line(
    colour = "#BDBDBD",
    linewidth = 0.7,
    alpha = 0.7
  ) +
  
  geom_point(
    colour = "#888888",
    size = 1.8
  ) +
  
  geom_line(
    data = filter(
      acc_chars,
      modelID %in% c("model8", "model11")
    ),
    aes(colour = modelID),
    linewidth = 1.3
  ) +
  
  geom_point(
    data = filter(
      acc_chars,
      modelID %in% c("model8", "model11")
    ),
    aes(colour = modelID),
    size = 2.8
  ) +
  
  scale_colour_manual(
    values = c(
      model8 = SCENARIO_COLORS["nt"],
      model11 = "#315872"
    ),
    labels = c(
      model8 = "M8 (NT baseline)",
      model11 = "M11"
    )
  ) +
  
  facet_wrap(
    ~scenario_label
  ) +
  
  scale_x_continuous(
    breaks = sort(unique(acc_chars$n_char))
  ) +
  
  labs(
    title = "Tree accuracy improves with increasing character count",
    subtitle = "All models are shown in grey; M8 and M11 are highlighted",
    x = "Number of characters",
    y = "Median CID",
    colour = NULL
  )

save_plot(
  p03,
  "tree_accuracy",
  "05_accuracy_by_character_count.png"
)

# ============================================================
# 04. TREE ACCURACY — IMPROVEMENT RELATIVE TO M1
# ============================================================

baseline_acc <- accuracy %>%
  filter(modelID == "model1") %>%
  select(
    scenario,
    baseline_cid = median_cid
  )

delta_acc <- accuracy %>%
  left_join(
    baseline_acc,
    by = "scenario"
  ) %>%
  mutate(
    improvement = baseline_cid - median_cid,
    model = factor(
      model,
      levels = paste0("M", 1:12)
    )
  )

p04 <- ggplot(
  delta_acc,
  aes(
    x = improvement,
    y = model,
    colour = scenario
  )
) +
  
  geom_vline(
    xintercept = 0,
    linetype = "dashed",
    colour = "#666666",
    linewidth = 0.5
  ) +
  
  geom_point(size = 3) +
  
  scale_colour_manual(
    values = SCENARIO_COLORS
  ) +
  
  labs(
    title = "Change in tree accuracy relative to the Mk baseline",
    subtitle = "Positive values indicate lower CID than M1",
    x = "Improvement in CID relative to M1",
    y = NULL,
    colour = NULL
  )

save_plot(
  p04,
  "tree_accuracy",
  "06_improvement_relative_to_mk.png"
)

# ============================================================
# 05. TREE ACCURACY — MODEL FAMILY
# ============================================================

family_acc <- accuracy %>%
  group_by(
    scenario,
    family
  ) %>%
  summarise(
    median_cid = median(median_cid, na.rm = TRUE),
    q1 = quantile(median_cid, 0.25, na.rm = TRUE),
    q3 = quantile(median_cid, 0.75, na.rm = TRUE),
    .groups = "drop"
  )

p05 <- ggplot(
  family_acc,
  aes(
    x = median_cid,
    y = fct_reorder(family, median_cid),
    colour = scenario
  )
) +
  
  geom_errorbar(
    aes(
      xmin = q1,
      xmax = q3
    ),
    orientation = "y",
    height = 0.18,
    linewidth = 0.9
  ) +
  
  geom_point(size = 3.4) +
  
  facet_wrap(~scenario) +
  
  scale_colour_manual(
    values = SCENARIO_COLORS
  ) +
  
  labs(
    title = "Tree accuracy by model family",
    subtitle = "Family-level summaries of median CID",
    x = "Clustering Information Distance",
    y = NULL,
    colour = NULL
  )

save_plot(
  p05,
  "tree_accuracy",
  "07_accuracy_by_model_family.png"
)

# ============================================================
# 06. TREE ACCURACY — MODEL × SCENARIO
# ============================================================

p06 <- ggplot(
  accuracy,
  aes(
    x = scenario_label,
    y = median_cid,
    group = model
  )
) +
  
  geom_line(
    colour = "#C5C5C5",
    linewidth = 0.7
  ) +
  
  geom_point(
    aes(colour = scenario),
    size = 2.8
  ) +
  
  scale_colour_manual(
    values = SCENARIO_COLORS
  ) +
  
  facet_wrap(~model, ncol = 4) +
  
  labs(
    title = "Change in tree accuracy between generative scenarios",
    subtitle = "Each panel shows one model across Mk- and NT-generated data",
    x = NULL,
    y = "Median CID",
    colour = NULL
  )

save_plot(
  p06,
  "tree_accuracy",
  "08_accuracy_scenario_change.png",
  width = 10,
  height = 8
)

# ============================================================
# RELATIVE MSE
# ============================================================

rel_mse <- ka %>%
  group_by(
    scenario,
    modelID
  ) %>%
  summarise(
    rel_mse =
      sum(mse_tree_len, na.rm = TRUE) /
      sum(tree_length^2, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(
    model = MODEL_LABELS[modelID],
    family = MODEL_FAMILY[modelID],
    scenario_label = recode(
      scenario,
      mk = "Mk-generated",
      nt = "NT-generated"
    )
  )

# ============================================================
# 07. RELATIVE MSE — RANKED DOT PLOT
# ============================================================

rel_mse_nt <- rel_mse %>%
  filter(scenario == "nt")

p07 <- ggplot(
  rel_mse_nt,
  aes(
    x = rel_mse,
    y = fct_reorder(model, rel_mse),
    colour = family
  )
) +
  
  geom_point(size = 3.4) +
  
  scale_x_log10() +
  
  scale_colour_manual(
    values = FAMILY_COLORS
  ) +
  
  labs(
    title = "Relative tree-length error under NT-generated data",
    subtitle = "Lower relative MSE indicates more accurate parameter recovery",
    x = "Relative MSE (log scale)",
    y = NULL,
    colour = "Model family"
  )

save_plot(
  p07,
  "known_answer",
  "06_relative_mse_dotplot.png"
)

# ============================================================
# 08. RELATIVE MSE — MK VS NT DUMBBELL
# ============================================================

mse_wide <- rel_mse %>%
  select(
    modelID,
    model,
    scenario,
    rel_mse
  ) %>%
  pivot_wider(
    names_from = scenario,
    values_from = rel_mse
  ) %>%
  filter(
    !is.na(mk),
    !is.na(nt)
  )

p08 <- ggplot(
  mse_wide,
  aes(
    y = fct_reorder(model, nt)
  )
) +
  
  geom_segment(
    aes(
      x = mk,
      xend = nt,
      yend = fct_reorder(model, nt)
    ),
    colour = "#C8C8C8",
    linewidth = 1
  ) +
  
  geom_point(
    aes(x = mk),
    colour = SCENARIO_COLORS["mk"],
    size = 3
  ) +
  
  geom_point(
    aes(x = nt),
    colour = SCENARIO_COLORS["nt"],
    size = 3
  ) +
  
  scale_x_log10() +
  
  labs(
    title = "Tree-length error across generative scenarios",
    subtitle = "Each line connects the same model under Mk- and NT-generated data",
    x = "Relative MSE (log scale)",
    y = NULL
  )

save_plot(
  p08,
  "known_answer",
  "07_relative_mse_mk_vs_nt.png"
)

# ============================================================
# 09. RELATIVE MSE — HEATMAP
# ============================================================

p09 <- ggplot(
  rel_mse,
  aes(
    x = scenario_label,
    y = factor(
      model,
      levels = paste0("M", 12:1)
    ),
    fill = rel_mse
  )
) +
  
  geom_tile(
    colour = "white",
    linewidth = 0.7
  ) +
  
  geom_text(
    aes(
      label = sprintf("%.3f", rel_mse)
    ),
    size = 3
  ) +
  
  scale_fill_viridis_c(
    option = "cividis",
    trans = "log10",
    name = "Relative MSE"
  ) +
  
  labs(
    title = "Relative tree-length error by model",
    subtitle = "Values are shown directly; darker shading indicates greater error",
    x = NULL,
    y = NULL
  ) +
  
  theme(
    panel.grid = element_blank()
  )

save_plot(
  p09,
  "known_answer",
  "08_relative_mse_heatmap.png",
  width = 8,
  height = 7
)

# ============================================================
# COVERAGE
# ============================================================

coverage <- cgr %>%
  filter(
    parameter == "tree_length"
  ) %>%
  group_by(
    scenario,
    modelID
  ) %>%
  summarise(
    coverage_rate = mean(
      coverage_rate,
      na.rm = TRUE
    ),
    .groups = "drop"
  ) %>%
  mutate(
    model = MODEL_LABELS[modelID],
    scenario_label = recode(
      scenario,
      mk = "Mk-generated",
      nt = "NT-generated"
    )
  )

# ============================================================
# 10. COVERAGE — DOT PLOT WITH 95% TARGET
# ============================================================

p10 <- ggplot(
  coverage,
  aes(
    x = coverage_rate,
    y = fct_reorder(model, coverage_rate),
    colour = scenario
  )
) +
  
  geom_vline(
    xintercept = 0.95,
    linetype = "dashed",
    colour = "#555555",
    linewidth = 0.7
  ) +
  
  geom_point(
    size = 3.2
  ) +
  
  scale_x_continuous(
    labels = percent_format(),
    limits = c(0, 1)
  ) +
  
  scale_colour_manual(
    values = SCENARIO_COLORS
  ) +
  
  labs(
    title = "Tree-length credible-interval coverage",
    subtitle = "Dashed line marks the nominal 95% coverage target",
    x = "Observed coverage",
    y = NULL,
    colour = NULL
  )

save_plot(
  p10,
  "cgr",
  "08_coverage_dotplot.png"
)

# ============================================================
# 11. COVERAGE — DEVIATION FROM 95%
# ============================================================

coverage_dev <- coverage %>%
  mutate(
    deviation = 100 * (coverage_rate - 0.95)
  )

p11 <- ggplot(
  coverage_dev,
  aes(
    x = deviation,
    y = fct_reorder(model, deviation),
    colour = scenario
  )
) +
  
  geom_vline(
    xintercept = 0,
    linetype = "dashed",
    colour = "#555555",
    linewidth = 0.7
  ) +
  
  geom_point(
    size = 3.2
  ) +
  
  scale_colour_manual(
    values = SCENARIO_COLORS
  ) +
  
  labs(
    title = "Deviation from nominal tree-length coverage",
    subtitle = "Zero represents the expected 95% coverage",
    x = "Difference from 95% coverage (percentage points)",
    y = NULL,
    colour = NULL
  )

save_plot(
  p11,
  "cgr",
  "09_coverage_deviation.png"
)

# ============================================================
# 12. COVERAGE — HEATMAP
# ============================================================

p12 <- ggplot(
  coverage,
  aes(
    x = scenario_label,
    y = factor(
      model,
      levels = paste0("M", 12:1)
    ),
    fill = coverage_rate
  )
) +
  
  geom_tile(
    colour = "white",
    linewidth = 0.7
  ) +
  
  geom_text(
    aes(
      label = sprintf(
        "%.1f%%",
        coverage_rate * 100
      )
    ),
    size = 3.1
  ) +
  
  scale_fill_viridis_c(
    option = "cividis",
    limits = c(0, 1),
    labels = percent_format(),
    name = "Coverage"
  ) +
  
  labs(
    title = "Tree-length credible-interval coverage",
    subtitle = "Observed coverage across models and generative scenarios",
    x = NULL,
    y = NULL
  ) +
  
  theme(
    panel.grid = element_blank()
  )

save_plot(
  p12,
  "cgr",
  "10_coverage_heatmap.png",
  width = 7,
  height = 7
)

# ============================================================
# 13. COVERAGE VS RELATIVE MSE
# ============================================================

coverage_mse <- coverage %>%
  select(
    scenario,
    modelID,
    model,
    coverage_rate
  ) %>%
  left_join(
    rel_mse %>%
      select(
        scenario,
        modelID,
        rel_mse
      ),
    by = c(
      "scenario",
      "modelID"
    )
  )

p13 <- ggplot(
  coverage_mse,
  aes(
    x = coverage_rate,
    y = rel_mse,
    colour = scenario,
    label = model
  )
) +
  
  geom_vline(
    xintercept = 0.95,
    linetype = "dashed",
    colour = "#777777"
  ) +
  
  geom_point(
    size = 3
  ) +
  
  geom_text(
    nudge_y = 0.04,
    size = 3,
    show.legend = FALSE
  ) +
  
  scale_x_continuous(
    labels = percent_format(),
    limits = c(0, 1)
  ) +
  
  scale_y_log10() +
  
  scale_colour_manual(
    values = SCENARIO_COLORS
  ) +
  
  labs(
    title = "Coverage and precision of tree-length estimates",
    subtitle = "Coverage alone does not describe the magnitude of parameter error",
    x = "Credible-interval coverage",
    y = "Relative MSE (log scale)",
    colour = NULL
  )

save_plot(
  p13,
  "cgr",
  "11_coverage_vs_mse.png"
)

# ============================================================
# THRESHOLDS
# ============================================================

thresholds <- bind_rows(
  thresh_mk,
  thresh_nt
) %>%
  mutate(
    model = MODEL_LABELS[modelID],
    scenario_label = recode(
      scenario,
      `Mk-generated` = "Mk-generated",
      `NT-generated` = "NT-generated",
      mk = "Mk-generated",
      nt = "NT-generated"
    ),
    predictor_label = recode(
      predictor,
      tree_length = "Tree length",
      rate_ratio = "Gain:loss ratio",
      chars_per_taxon = "Characters per taxon"
    )
  )

# ============================================================
# 14. THRESHOLD HEATMAP — CLEANER VERSION
# ============================================================

thresholds <- thresholds %>%
  mutate(
    threshold_found = !is.na(threshold)
  )

p14 <- ggplot(
  thresholds,
  aes(
    x = predictor_label,
    y = factor(
      model,
      levels = paste0("M", 12:1)
    ),
    fill = threshold_found
  )
) +
  
  geom_tile(
    colour = "white",
    linewidth = 0.7
  ) +
  
  geom_text(
    aes(
      label = ifelse(
        threshold_found,
        sprintf("%.2f", threshold),
        "—"
      )
    ),
    size = 3.2,
    colour = ifelse(
      thresholds$threshold_found,
      "white",
      "#777777"
    )
  ) +
  
  facet_wrap(
    ~scenario_label
  ) +
  
  scale_fill_manual(
    values = c(
      `TRUE` = "#3B6F8F",
      `FALSE` = "#E5E5E5"
    ),
    guide = "none"
  ) +
  
  labs(
    title = "Detected performance thresholds",
    subtitle = "Values show the predictor value at which a model comparison changes sign",
    x = NULL,
    y = NULL
  ) +
  
  theme(
    panel.grid = element_blank()
  )

save_plot(
  p14,
  "gam_threshold",
  "15_threshold_heatmap_clean.png",
  width = 9,
  height = 7
)

# ============================================================
# 15. THRESHOLD POINT PLOT
# ============================================================

threshold_points <- thresholds %>%
  filter(
    !is.na(threshold)
  )

p15 <- ggplot(
  threshold_points,
  aes(
    x = threshold,
    y = fct_reorder(
      model,
      threshold
    ),
    colour = predictor_label
  )
) +
  
  geom_point(
    size = 3.2
  ) +
  
  facet_wrap(
    ~scenario_label
  ) +
  
  scale_colour_brewer(
    palette = "Dark2"
  ) +
  
  labs(
    title = "Detected performance thresholds",
    subtitle = "Only comparisons with a detectable threshold within the tested range are shown",
    x = "Threshold value",
    y = NULL,
    colour = "Predictor"
  )

save_plot(
  p15,
  "gam_threshold",
  "16_threshold_points.png"
)

# ============================================================
# 16. THRESHOLD PLOT BY PREDICTOR
# ============================================================

p16 <- ggplot(
  threshold_points,
  aes(
    x = threshold,
    y = fct_reorder(
      model,
      threshold
    ),
    colour = scenario
  )
) +
  
  geom_point(
    size = 3
  ) +
  
  facet_wrap(
    ~predictor_label,
    scales = "free_x"
  ) +
  
  scale_colour_manual(
    values = SCENARIO_COLORS
  ) +
  
  labs(
    title = "Threshold locations across predictors",
    subtitle = "Thresholds are shown separately for each predictor",
    x = "Threshold value",
    y = NULL,
    colour = NULL
  )

save_plot(
  p16,
  "gam_threshold",
  "17_threshold_by_predictor.png",
  width = 10,
  height = 7
)

# ============================================================
# 17. MODEL RANKING — BOTH SCENARIOS
# ============================================================

ranking <- accuracy %>%
  group_by(scenario) %>%
  arrange(
    median_cid,
    .by_group = TRUE
  ) %>%
  mutate(
    rank = row_number()
  ) %>%
  ungroup()

p17 <- ggplot(
  ranking,
  aes(
    x = rank,
    y = median_cid,
    colour = scenario
  )
) +
  
  geom_line(
    aes(group = scenario),
    linewidth = 0.8
  ) +
  
  geom_point(
    size = 3
  ) +
  
  scale_x_continuous(
    breaks = 1:12
  ) +
  
  scale_colour_manual(
    values = SCENARIO_COLORS
  ) +
  
  labs(
    title = "Model accuracy ranking",
    subtitle = "Models are ordered from lowest to highest median CID within each scenario",
    x = "Model rank",
    y = "Median CID",
    colour = NULL
  )

save_plot(
  p17,
  "tree_accuracy",
  "09_model_rank_curve.png"
)

# ============================================================
# 18. MODEL FAMILY — RELATIVE MSE
# ============================================================

family_mse <- rel_mse %>%
  group_by(
    scenario,
    family
  ) %>%
  summarise(
    rel_mse = median(
      rel_mse,
      na.rm = TRUE
    ),
    .groups = "drop"
  )

p18 <- ggplot(
  family_mse,
  aes(
    x = rel_mse,
    y = fct_reorder(
      family,
      rel_mse
    ),
    colour = scenario
  )
) +
  
  geom_point(
    size = 3.5
  ) +
  
  scale_x_log10() +
  
  scale_colour_manual(
    values = SCENARIO_COLORS
  ) +
  
  labs(
    title = "Tree-length error by model family",
    subtitle = "Median relative MSE within each model family",
    x = "Relative MSE (log scale)",
    y = NULL,
    colour = NULL
  )

save_plot(
  p18,
  "known_answer",
  "09_relative_mse_by_family.png"
)

# ============================================================
# 19. ACCURACY VS RELATIVE MSE
# ============================================================

accuracy_mse <- accuracy %>%
  select(
    scenario,
    modelID,
    model,
    median_cid
  ) %>%
  left_join(
    rel_mse %>%
      select(
        scenario,
        modelID,
        rel_mse
      ),
    by = c(
      "scenario",
      "modelID"
    )
  )

p19 <- ggplot(
  accuracy_mse,
  aes(
    x = median_cid,
    y = rel_mse,
    colour = scenario,
    label = model
  )
) +
  
  geom_point(
    size = 3
  ) +
  
  geom_text(
    nudge_y = 0.04,
    size = 3,
    show.legend = FALSE
  ) +
  
  scale_y_log10() +
  
  scale_colour_manual(
    values = SCENARIO_COLORS
  ) +
  
  labs(
    title = "Tree accuracy and tree-length parameter error",
    subtitle = "Topology accuracy and parameter recovery provide different measures of model performance",
    x = "Median CID",
    y = "Relative tree-length MSE (log scale)",
    colour = NULL
  )

save_plot(
  p19,
  "cgr",
  "12_accuracy_vs_parameter_error.png"
)

# ============================================================
# 20. SAVE A SIMPLE MODEL FAMILY LEGEND FIGURE
# ============================================================

family_key <- tibble(
  family = factor(
    names(FAMILY_COLORS),
    levels = names(FAMILY_COLORS)
  ),
  value = 1
)

p20 <- ggplot(
  family_key,
  aes(
    x = family,
    y = value,
    fill = family
  )
) +
  
  geom_col(
    width = 0.65
  ) +
  
  scale_fill_manual(
    values = FAMILY_COLORS
  ) +
  
  labs(
    title = "Model families",
    x = NULL,
    y = NULL,
    fill = NULL
  ) +
  
  theme_matrix() +
  
  theme(
    axis.text.y = element_blank(),
    axis.ticks = element_blank(),
    panel.grid = element_blank()
  )

save_plot(
  p20,
  "tree_accuracy",
  "10_model_family_key.png",
  width = 8,
  height = 4
)

# ============================================================
# SUMMARY
# ============================================================

cat("\n")
cat("============================================================\n")
cat("BETTER FIGURES COMPLETE\n")
cat("============================================================\n\n")

cat("Tree accuracy:\n")
cat("  03_accuracy_dotplot.png\n")
cat("  04_accuracy_character_heatmap.png\n")
cat("  05_accuracy_by_character_count.png\n")
cat("  06_improvement_relative_to_mk.png\n")
cat("  07_accuracy_by_model_family.png\n")
cat("  08_accuracy_scenario_change.png\n")
cat("  09_model_rank_curve.png\n")
cat("  10_model_family_key.png\n\n")

cat("Relative MSE:\n")
cat("  06_relative_mse_dotplot.png\n")
cat("  07_relative_mse_mk_vs_nt.png\n")
cat("  08_relative_mse_heatmap.png\n")
cat("  09_relative_mse_by_family.png\n\n")

cat("Coverage / parameter recovery:\n")
cat("  08_coverage_dotplot.png\n")
cat("  09_coverage_deviation.png\n")
cat("  10_coverage_heatmap.png\n")
cat("  11_coverage_vs_mse.png\n")
cat("  12_accuracy_vs_parameter_error.png\n\n")

cat("Thresholds:\n")
cat("  15_threshold_heatmap_clean.png\n")
cat("  16_threshold_points.png\n")
cat("  17_threshold_by_predictor.png\n\n")

cat("All figures saved under:\n")
cat(FIG_DIR, "\n")