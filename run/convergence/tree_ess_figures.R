# Two new figures supporting the convergence sensitivity check and the
# tree-ESS finding for Model 11.

source("R/core/_setup.R")
source("run/shared/config_theme.R")
library(dplyr)
library(ggplot2)
library(tidyr)

conv <- readRDS(PATHS$convergence)
conv <- conv %>%
  mutate(
    rhat_pass_v2     = !is.na(rhat_max) & rhat_max <= 1.02,
    ess_pass_v2      = !is.na(ess_min) & ess_min > 200,
    tree_ess_pass_v2 = !is.na(tree_ess) & tree_ess > 100,
    asdsf_pass_v2    = !is.na(asdsf) & asdsf < 0.05,
    pass_v2          = rhat_pass_v2 & ess_pass_v2 & tree_ess_pass_v2 & asdsf_pass_v2
  )

model_labels <- c(model1="M1",model2="M2",model3="M3",model4="M4",model5="M5",
                   model6="M6",model7="M7",model8="M8 (NT)",model9="M9",
                   model10="M10",model11="M11",model12="M12")

# --- Figure A: original vs relaxed+tree-ESS pass rate, grouped bar, by model x scenario ---
pass_tab <- conv %>%
  group_by(scenario, modelID) %>%
  summarise(orig = mean(pass)*100, v2 = mean(pass_v2)*100, .groups = "drop") %>%
  pivot_longer(c(orig, v2), names_to = "rule", values_to = "pass_rate") %>%
  mutate(rule = recode(rule, orig = "Original (ESS>256)", v2 = "Relaxed ESS>200 + tree-ESS>100"),
         model_label = factor(model_labels[modelID], levels = model_labels))

pA <- ggplot(pass_tab, aes(x = model_label, y = pass_rate, fill = rule)) +
  geom_col(position = position_dodge(width = 0.75), width = 0.7) +
  facet_wrap(~scenario, ncol = 1, labeller = labeller(scenario = c(mk="Mk-generated", nt="NT-generated"))) +
  scale_fill_manual(values = c("Original (ESS>256)" = "#4C72B0",
                                "Relaxed ESS>200 + tree-ESS>100" = "#DD8452")) +
  labs(title = "Convergence pass rate: original screen vs relaxed ESS + tree-ESS screen",
       subtitle = "Adding a tree-ESS criterion (previously unused) reduces Model 11 and Model 12's\npass rate despite the relaxed continuous-parameter ESS threshold",
       x = NULL, y = "Pass rate (%)", fill = NULL) +
  theme_minimal(base_size = 12) +
  theme(legend.position = "top", axis.text.x = element_text(angle = 0))

ggsave(file.path(PATHS$fig_dir, "convergence", "10_pass_rate_original_vs_relaxed.png"),
       pA, width = 9, height = 6, dpi = 300)

# --- Figure B: tree-ESS distribution by model, highlighting Model 11 ---
conv <- conv %>% mutate(model_label = factor(model_labels[modelID], levels = model_labels))

pB <- ggplot(conv, aes(x = model_label, y = tree_ess, fill = modelID %in% c("model11","model12"))) +
  geom_boxplot(outlier.size = 0.5, outlier.alpha = 0.3) +
  geom_hline(yintercept = 100, linetype = "dashed", colour = "grey40") +
  annotate("text", x = 1, y = 130, label = "proposed tree-ESS threshold (100)",
           hjust = 0, size = 3, colour = "grey40") +
  scale_fill_manual(values = c(`FALSE` = "#4C72B0", `TRUE` = "#C44E52"),
                     guide = "none") +
  labs(title = "Tree effective sample size by model, pooled across both scenarios",
       subtitle = "Model 11 has the lowest median tree-ESS of all twelve models despite\nranking first on tree accuracy -- a mixing/exploration caveat on that result",
       x = NULL, y = "Tree ESS") +
  theme_minimal(base_size = 12)

ggsave(file.path(PATHS$fig_dir, "convergence", "11_tree_ess_by_model.png"),
       pB, width = 9, height = 5.5, dpi = 300)

cat("Saved figures to", file.path(PATHS$fig_dir, "convergence"), "\n")
