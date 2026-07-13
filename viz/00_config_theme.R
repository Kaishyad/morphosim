## ============================================================
## 00_config_theme.R
## Shared config, palette, and ggplot theme for morphosim/viz.
##
## Run everything from the morphosim repo root, e.g.:
##   Rscript viz/01_tree_accuracy_plots.R
##
## Source this at the top of every other script:
##   source("viz/00_config_theme.R")
##
## This sources R/core/_setup.R (the real pipeline setup), so it picks up
## OutputDir()/MatrixDir()/GridTag()/ScenarioGrid()/PARAM_GRID/MODEL_IDS and
## the ESS/R-hat/ASDSF thresholds exactly as the analysis pipeline uses them.
## The-matrix is assumed to be a sibling directory of morphosim
## (../the-matrix), same convention as R/core/_setup.R. Override with
## Sys.setenv(MORPHOSIM_MATRIX_DIR = "/path/to/the-matrix") before sourcing
## this file if your layout differs.
## ============================================================

if (!file.exists("R/core/_setup.R")) {
  stop("Run viz scripts from the morphosim repo root (R/core/_setup.R not found ",
       "relative to ", getwd(), ").")
}

# --- Point at the-matrix before _setup.R sets its options, if overridden
matrix_override <- Sys.getenv("MORPHOSIM_MATRIX_DIR", unset = NA)
if (!is.na(matrix_override)) options("ntOutDir" = matrix_override)

source("R/core/_setup.R")   # brings in OutputDir(), GridTag(), ScenarioGrid(),
                             # PARAM_GRID, MODEL_IDS, ESS_MIN, RHAT_MAX, ASDSF_MAX

suppressPackageStartupMessages({
  library(tidyverse)
  library(scales)
})

# ---------------------------------------------------------------
# PATHS -- real outputs written by run/*.R into the-matrix/results/,
# figures written back out to the-matrix/figures/ (code stays in
# morphosim, outputs live in the-matrix, per project convention).
# ---------------------------------------------------------------
.results_dir <- file.path(OutputDir(), "results")

PATHS <- list(
  results_dir       = .results_dir,
  convergence       = file.path(.results_dir, "convergence_summary.rds"),        # run/check_convergence.R (+ merge_convergence.R)
  tree_accuracy_rep = file.path(.results_dir, "tree_accuracy_per_rep.rds"),      # run/tree_accuracy.R (+ merge_tree_accuracy.R)
  tree_accuracy_sum = file.path(.results_dir, "tree_accuracy_summary.rds"),      # grid-cell summary, includes PARAM_GRID columns
  threshold_mk      = file.path(.results_dir, "threshold_summary_mk.rds"),      # run/gam_threshold.R
  threshold_nt      = file.path(.results_dir, "threshold_summary_nt.rds"),      # run/gam_threshold.R
  imputation_sum    = file.path(.results_dir, "imputation_accuracy.rds"),       # analysis/imputation_analysis.R
  imputation_rep    = file.path(.results_dir, "imputation_accuracy_per_rep.rds"),
  imputation_wilcox = file.path(.results_dir, "imputation_wilcoxon.rds"),
  known_answer      = file.path(.results_dir, "known_answer_summary.rds"),      # run/known_answer.R
  cgr_coverage      = file.path(.results_dir, "cgr_coverage.rds"),              # run/validate_cgr.R
  cross_metric_cell = file.path(.results_dir, "cross_metric_gridcell.rds"),     # run/cross_metric_analysis.R
  cross_metric_model = file.path(.results_dir, "cross_metric_model_scorecard.rds"),
  cross_metric_rank_corr = file.path(.results_dir, "cross_metric_rank_correlations.rds"),
  cross_metric_cell_corr = file.path(.results_dir, "cross_metric_gridcell_correlations.rds"),
  fig_dir           = file.path(OutputDir(), "figures")
)

dir.create(PATHS$fig_dir, showWarnings = FALSE, recursive = TRUE)

# ---------------------------------------------------------------
# MODEL LABELS -- real model IDs are "model1".."model12" (lowercase).
# Edit the RHS strings if you want fuller descriptions per model; the
# two baselines are pre-filled since they're referenced throughout.
# ---------------------------------------------------------------
MODEL_LABELS <- setNames(
  paste0("M", 1:12),
  MODEL_IDS
)
MODEL_LABELS["model1"] <- "M1 (Mk baseline)"
MODEL_LABELS["model8"] <- "M8 (NT baseline)"

# ---------------------------------------------------------------
# BASELINES -- per your framework, model1 is the Mk baseline and is
# only meaningful for the "mk" generative scenario; model8 is the NT
# baseline and is the meaningful reference for the "nt" scenario.
# Every plot that shows a delta/relative-to-baseline view below looks
# this up per scenario rather than assuming a single global baseline.
# Absolute/ranking plots are kept alongside the baseline-relative ones
# so no model's performance is only ever seen framed against a baseline.
#
# FIX (2026-07): BASELINE_BY_SCENARIO used to be defined here AND
# (independently, hardcoded to "model1" for both scenarios) inside
# run/gam_threshold.R and R/analysis/ThresholdGAM.R -- two copies of the
# same idea that had drifted out of sync. It's now defined exactly once,
# in R/core/Grid.R, which R/core/_setup.R (sourced above) already brings
# in, so nothing further needs defining here. If you ever see
# "BASELINE_BY_SCENARIO not found" it means R/core/Grid.R didn't load --
# check R/core/_setup.R's source loop picked it up.

# ---------------------------------------------------------------
# PALETTE + THEME
# ---------------------------------------------------------------
SCENARIO_COLORS <- c(mk = "#2C7FB8", nt = "#D95F02")

model_palette <- function(n = 12) {
  grDevices::colorRampPalette(c("#2C7FB8", "#41AB5D", "#D95F02", "#984EA3"))(n)
}

theme_matrix <- function(base_size = 12) {
  theme_minimal(base_size = base_size) +
    theme(
      plot.title       = element_text(face = "bold", size = rel(1.15), margin = margin(b = 6)),
      plot.subtitle    = element_text(color = "grey35", size = rel(0.9), margin = margin(b = 10)),
      plot.caption     = element_text(color = "grey50", size = rel(0.7)),
      panel.grid.minor = element_blank(),
      panel.grid.major = element_line(color = "grey90", linewidth = 0.3),
      strip.text       = element_text(face = "bold", size = rel(0.95)),
      strip.background = element_rect(fill = "grey95", color = NA),
      legend.position  = "bottom",
      legend.title     = element_text(face = "bold", size = rel(0.85)),
      axis.title       = element_text(size = rel(0.95))
    )
}
theme_set(theme_matrix())

# ---------------------------------------------------------------
# SAVE HELPER -- consistent sizing / dpi / dual format output
# ---------------------------------------------------------------
save_fig <- function(plot, name, width = 8, height = 5.5, dpi = 300, formats = c("png", "pdf")) {
  for (fmt in formats) {
    ggsave(
      filename = file.path(PATHS$fig_dir, paste0(name, ".", fmt)),
      plot = plot, width = width, height = height, dpi = dpi, bg = "white"
    )
  }
  message("Saved: ", name, " (", paste(formats, collapse = ", "), ") -> ", PATHS$fig_dir)
}

# ---------------------------------------------------------------
# SAFE READERS -- warn instead of hard-failing if a file is missing,
# so one not-yet-run pipeline step doesn't stop the whole viz suite.
# Primary outputs are .rds (saveRDS/readRDS); threshold_summary_*
# also exists as .csv, kept as a fallback reader.
# ---------------------------------------------------------------
safe_read_rds <- function(path) {
  if (!file.exists(path)) {
    warning("Missing file: ", path, " -- skipping plots that depend on it.")
    return(NULL)
  }
  readRDS(path)
}

safe_read_csv <- function(path) {
  if (!file.exists(path)) {
    warning("Missing file: ", path, " -- skipping plots that depend on it.")
    return(NULL)
  }
  readr::read_csv(path, show_col_types = FALSE)
}

# ---------------------------------------------------------------
# LABEL HELPER -- factor a modelID column using MODEL_LABELS, keeping
# only levels actually present so facets/legends don't pad out to all
# 12 when a data set only covers a subset.
# ---------------------------------------------------------------
label_models <- function(df, col = "modelID") {
  present <- intersect(MODEL_IDS, unique(df[[col]]))
  df[[col]] <- factor(df[[col]], levels = present, labels = MODEL_LABELS[present])
  df
}
