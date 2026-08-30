#Shared config, palette, and ggplot theme for morphosim/viz.

if (!file.exists("R/core/_setup.R")) {
  stop("Run viz scripts from the morphosim repo root (R/core/_setup.R not found ",
       "relative to ", getwd(), ").")
}

# Point at the-matrix before _setup.R sets its options, if overridden
matrix_override <- Sys.getenv("MORPHOSIM_MATRIX_DIR", unset = NA)
if (!is.na(matrix_override)) options("ntOutDir" = matrix_override)

source("R/core/_setup.R") 

suppressPackageStartupMessages({
  library(tidyverse)
  library(scales)
})

.results_dir <- file.path(OutputDir(), "results")

PATHS <- list(
  results_dir       = .results_dir,
  convergence       = file.path(.results_dir, "convergence_summary.rds"),        # run/check_convergence.R (+ merge_convergence.R) -- shared top-level file, no subfolder
  tree_accuracy_rep = file.path(.results_dir, "tree_accuracy", "tree_accuracy_per_rep.rds"),      # run/tree_accuracy.R (+ merge_tree_accuracy.R)
  tree_accuracy_sum = file.path(.results_dir, "tree_accuracy", "tree_accuracy_summary.rds"),      # grid-cell summary, includes PARAM_GRID columns
  threshold_mk      = file.path(.results_dir, "gam_threshold", "threshold_summary_mk.rds"),      # run/gam_threshold.R
  threshold_nt      = file.path(.results_dir, "gam_threshold", "threshold_summary_nt.rds"),      # run/gam_threshold.R
  imputation_sum    = file.path(.results_dir, "imputation_accuracy.rds"),       # run/imputation/imputation_analysis.R
  imputation_rep    = file.path(.results_dir, "imputation_accuracy_per_rep.rds"),
  imputation_wilcox = file.path(.results_dir, "imputation_wilcoxon.rds"),
  known_answer      = file.path(.results_dir, "known_answer", "known_answer_summary.rds"),      # run/known_answer.R
  cgr_coverage      = file.path(.results_dir, "cgr", "cgr_coverage.rds"),              # run/validate_cgr.R
  cross_metric_cell = file.path(.results_dir, "cross_metric", "cross_metric_gridcell.rds"),     # run/cross_metric_analysis.R
  cross_metric_model = file.path(.results_dir, "cross_metric", "cross_metric_model_scorecard.rds"),
  cross_metric_rank_corr = file.path(.results_dir, "cross_metric", "cross_metric_rank_correlations.rds"),
  cross_metric_cell_corr = file.path(.results_dir, "cross_metric", "cross_metric_gridcell_correlations.rds"),
  fig_dir           = file.path(OutputDir(), "figures")
)

dir.create(PATHS$fig_dir, showWarnings = FALSE, recursive = TRUE)

# MODEL LABELS
MODEL_LABELS <- setNames(
  paste0("M", 1:12),
  MODEL_IDS
)
MODEL_LABELS["model1"] <- "M1 (Mk baseline)"
MODEL_LABELS["model8"] <- "M8 (NT baseline)"

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

save_fig <- function(plot, name, subdir = "", width = 8, height = 5.5, dpi = 300, formats = c("png")) {
  out_dir <- if (nzchar(subdir)) file.path(PATHS$fig_dir, subdir) else PATHS$fig_dir
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  for (fmt in formats) {
    ggsave(
      filename = file.path(out_dir, paste0(name, ".", fmt)),
      plot = plot, width = width, height = height, dpi = dpi, bg = "white"
    )
  }
  message("Saved: ", name, " (", paste(formats, collapse = ", "), ") -> ", out_dir)
}

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

label_models <- function(df, col = "modelID") {
  present <- intersect(MODEL_IDS, unique(df[[col]]))
  df[[col]] <- factor(df[[col]], levels = present, labels = MODEL_LABELS[present])
  df
}
