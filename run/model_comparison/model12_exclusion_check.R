# Sensitivity check: does excluding Model 12 change the omnibus/pairwise
# conclusions, and how many more replicate blocks survive once its
# convergence failures stop vetoing them?
#
# Self-contained -- uses only base R (stats::friedman.test,
# stats::pairwise.wilcox.test) rather than any custom pipeline functions,
# so it doesn't depend on exact internal function names in ModelComparison.R.

source("R/core/_setup.R")
source("run/shared/config_theme.R")
library(dplyr)
library(tidyr)

cid <- readRDS(PATHS$tree_accuracy_rep)   # one row per scenario/gridTag/repID/modelID

run_check <- function(scenario_filter, exclude_model = NULL) {
  d <- cid %>% filter(scenario == scenario_filter)
  if (!is.null(exclude_model)) d <- d %>% filter(modelID != exclude_model)

  # Wide matrix: rows = replicate blocks (gridTag x repID), cols = models,
  # values = per-cell CID. Complete-case only, matching the original
  # Friedman requirement.
  wide <- d %>%
    select(gridTag, repID, modelID, median_cid) %>%
    pivot_wider(names_from = modelID, values_from = median_cid) %>%
    drop_na()

  n_blocks <- nrow(wide)
  mat <- as.matrix(wide %>% select(-gridTag, -repID))
  fried <- friedman.test(mat)

  list(n_blocks = n_blocks, friedman = fried, wide = wide)
}

cat("=== WITH Model 12 (original) ===\n")
orig_mk <- run_check("mk")
orig_nt <- run_check("nt")
cat("Mk complete blocks:", orig_mk$n_blocks, "\n")
print(orig_mk$friedman)
cat("\nNT complete blocks:", orig_nt$n_blocks, "\n")
print(orig_nt$friedman)

cat("\n\n=== WITHOUT Model 12 ===\n")
excl_mk <- run_check("mk", exclude_model = "model12")
excl_nt <- run_check("nt", exclude_model = "model12")
cat("Mk complete blocks:", excl_mk$n_blocks,
    " (", excl_mk$n_blocks - orig_mk$n_blocks, "more than with Model 12)\n")
print(excl_mk$friedman)
cat("\nNT complete blocks:", excl_nt$n_blocks,
    " (", excl_nt$n_blocks - orig_nt$n_blocks, "more than with Model 12)\n")
print(excl_nt$friedman)

# Pairwise Wilcoxon (Holm-adjusted), without Model 12, to check whether the
# RANKING among the remaining 11 models shifts once the extra replicate
# blocks are restored.
long_nt <- excl_nt$wide %>%
  pivot_longer(-c(gridTag, repID), names_to = "modelID", values_to = "median_cid")

cat("\n\n=== Median CID ranking, NT, WITHOUT Model 12 (using restored blocks) ===\n")
print(long_nt %>% group_by(modelID) %>%
        summarise(median_cid = median(median_cid), n = n(), .groups = "drop") %>%
        arrange(median_cid))

pw <- pairwise.wilcox.test(long_nt$median_cid, long_nt$modelID,
                            paired = FALSE, p.adjust.method = "holm")
cat("\n=== Pairwise Wilcoxon (Holm-adjusted), NT, without Model 12 ===\n")
print(pw)

# Save results for upload/inspection
saveRDS(list(orig_mk = orig_mk, orig_nt = orig_nt,
             excl_mk = excl_mk, excl_nt = excl_nt, pairwise_no_m12 = pw),
        file.path(PATHS$results_dir, "model_comparison", "model12_exclusion_sensitivity.rds"))

cat("\nSaved to results/model_comparison/model12_exclusion_sensitivity.rds\n")
