# Model 12 exclusion sensitivity check -- PAIRED version, matching the
# Methodology's actual test (paired Wilcoxon signed-rank on matched
# replicate blocks, Holm-adjusted across all pairwise comparisons),
# not the unpaired rank-sum test used in the earlier quick check.

source("R/core/_setup.R")
source("run/shared/config_theme.R")
library(dplyr)
library(tidyr)

cid <- readRDS(PATHS$tree_accuracy_rep)

# Wide matrix, NT scenario, Model 12 excluded, complete cases only
wide <- cid %>%
  filter(scenario == "nt", modelID != "model12") %>%
  select(gridTag, repID, modelID, median_cid) %>%
  pivot_wider(names_from = modelID, values_from = median_cid) %>%
  drop_na()

cat("Complete NT replicate blocks without Model 12:", nrow(wide), "\n\n")

models <- setdiff(colnames(wide), c("gridTag", "repID"))
pairs <- combn(models, 2, simplify = FALSE)

results <- lapply(pairs, function(p) {
  x <- wide[[p[1]]]; y <- wide[[p[2]]]
  test <- wilcox.test(x, y, paired = TRUE)
  data.frame(model_a = p[1], model_b = p[2], p_raw = test$p.value)
})
results <- bind_rows(results)
results$p_holm <- p.adjust(results$p_raw, method = "holm")

cat("=== Full paired, Holm-adjusted pairwise comparisons (Model 12 excluded) ===\n")
print(as.data.frame(results %>% arrange(p_holm)))

cat("\n=== Comparisons specifically against Model 8 (the NT baseline) ===\n")
vs_m8 <- results %>% filter(model_a == "model8" | model_b == "model8") %>%
  mutate(other = ifelse(model_a == "model8", model_b, model_a)) %>%
  select(other, p_raw, p_holm) %>% arrange(p_holm)
print(as.data.frame(vs_m8))

# Re-rank medians using this same complete-case sample, for direct
# comparison against the original (Model-12-included) ranking
ranking <- wide %>%
  pivot_longer(-c(gridTag, repID), names_to = "modelID", values_to = "median_cid") %>%
  group_by(modelID) %>%
  summarise(median_cid = median(median_cid), .groups = "drop") %>%
  arrange(median_cid) %>%
  mutate(rank = row_number())

cat("\n=== Re-ranked median CID, NT, Model 12 excluded (paired-complete sample) ===\n")
print(as.data.frame(ranking))

saveRDS(list(pairwise = results, vs_m8 = vs_m8, ranking = ranking, n_blocks = nrow(wide)),
        file.path(PATHS$results_dir, "model_comparison", "model12_exclusion_paired.rds"))
cat("\nSaved to results/model_comparison/model12_exclusion_paired.rds\n")
