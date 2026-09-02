# Full convergence-diagnostic comparison across all twelve models.
# Produces per-model summaries for every diagnostic (R-hat, continuous-parameter
# ESS, tree-topology ESS, ASDSF), plus breakdowns by tree_length and n_char,
# since both diagnostics are already known to interact with those two axes
# (Section 1 findings: pass rate falls with tree_length and n_char; Model 11/12
# tree-ESS issue found so far only by inspection, not a full comparison).
#
# Writes several CSVs to results/convergence/ -- upload these back for analysis
# rather than pasting console output, since several are wide/long tables.

source("R/core/_setup.R")
source("run/shared/config_theme.R")
library(dplyr)
library(readr)
library(tidyr)

conv <- readRDS(PATHS$convergence)
conv <- conv %>%
  mutate(
    tree_length = as.numeric(stringr::str_extract(gridTag, "(?<=tl)[\\d.]+")),
    n_char      = as.numeric(stringr::str_extract(gridTag, "(?<=c)\\d+$")),
    gain_loss   = as.numeric(stringr::str_extract(gridTag, "(?<=gl)[\\d.]+")),
    part_rate   = as.numeric(stringr::str_extract(gridTag, "(?<=pr)[\\d.]+"))
  )

out_dir <- file.path(PATHS$results_dir, "convergence")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# --- 1. Overall per-model, per-scenario summary across all four diagnostics ---
overall <- conv %>%
  group_by(scenario, modelID) %>%
  summarise(
    n_runs           = n(),
    pass_rate        = mean(pass) * 100,
    mean_rhat_max    = mean(rhat_max, na.rm = TRUE),
    p95_rhat_max     = quantile(rhat_max, 0.95, na.rm = TRUE),
    mean_ess_min     = mean(ess_min, na.rm = TRUE),
    median_ess_min   = median(ess_min, na.rm = TRUE),
    p05_ess_min      = quantile(ess_min, 0.05, na.rm = TRUE),
    mean_tree_ess    = mean(tree_ess, na.rm = TRUE),
    median_tree_ess  = median(tree_ess, na.rm = TRUE),
    p05_tree_ess     = quantile(tree_ess, 0.05, na.rm = TRUE),
    mean_asdsf       = mean(asdsf, na.rm = TRUE),
    p95_asdsf        = quantile(asdsf, 0.95, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(scenario, median_tree_ess)

write_csv(overall, file.path(out_dir, "diagnostics_by_model_overall.csv"))

# --- 2. Tree-ESS specifically, by model x tree_length (does the low-tree-ESS
#         problem concentrate at particular tree lengths, for EVERY model) ---
tree_ess_by_tl <- conv %>%
  group_by(scenario, modelID, tree_length) %>%
  summarise(median_tree_ess = median(tree_ess, na.rm = TRUE),
            p05_tree_ess    = quantile(tree_ess, 0.05, na.rm = TRUE),
            n = n(), .groups = "drop") %>%
  arrange(scenario, modelID, tree_length)

write_csv(tree_ess_by_tl, file.path(out_dir, "tree_ess_by_model_treelength.csv"))

# --- 3. Tree-ESS by model x n_char (does it degrade with more characters,
#         mirroring the pass-rate pattern already found for Model 12) ---
tree_ess_by_nchar <- conv %>%
  group_by(scenario, modelID, n_char) %>%
  summarise(median_tree_ess = median(tree_ess, na.rm = TRUE),
            p05_tree_ess    = quantile(tree_ess, 0.05, na.rm = TRUE),
            n = n(), .groups = "drop") %>%
  arrange(scenario, modelID, n_char)

write_csv(tree_ess_by_nchar, file.path(out_dir, "tree_ess_by_model_nchar.csv"))

# --- 4. Continuous-parameter ESS (ess_min), same breakdowns, for direct
#         side-by-side comparison against tree_ess in the same model/axis cell ---
ess_min_by_tl <- conv %>%
  group_by(scenario, modelID, tree_length) %>%
  summarise(median_ess_min = median(ess_min, na.rm = TRUE),
            p05_ess_min    = quantile(ess_min, 0.05, na.rm = TRUE),
            n = n(), .groups = "drop") %>%
  arrange(scenario, modelID, tree_length)

write_csv(ess_min_by_tl, file.path(out_dir, "ess_min_by_model_treelength.csv"))

# --- 5. Direct ratio: tree_ess / ess_min per model (are the two diagnostics
#         correlated, or does the ranking of models differ substantially
#         depending on which ESS you look at?) ---
ratio_tab <- conv %>%
  filter(!is.na(tree_ess), !is.na(ess_min), ess_min > 0) %>%
  group_by(scenario, modelID) %>%
  summarise(median_ratio_tree_to_cont = median(tree_ess / ess_min, na.rm = TRUE),
            .groups = "drop") %>%
  arrange(scenario, median_ratio_tree_to_cont)

write_csv(ratio_tab, file.path(out_dir, "tree_ess_to_ess_min_ratio_by_model.csv"))

cat("Wrote 5 CSVs to", out_dir, "\n")
cat("- diagnostics_by_model_overall.csv\n")
cat("- tree_ess_by_model_treelength.csv\n")
cat("- tree_ess_by_model_nchar.csv\n")
cat("- ess_min_by_model_treelength.csv\n")
cat("- tree_ess_to_ess_min_ratio_by_model.csv\n")
