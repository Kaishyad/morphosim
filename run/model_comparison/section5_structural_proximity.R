# Section 5 figure: does structural proximity to NT predict accuracy?
# Matches the visual style of the existing tree_accuracy/ figures (ggplot2, clean theme).
# Reads from the already-merged tree_accuracy_summary / model_comparison_ranking outputs.

source("R/core/_setup.R")
source("run/shared/config_theme.R")
library(dplyr)
library(ggplot2)
library(readr)

ranking <- read_csv(file.path(PATHS$results_dir, "model_comparison", "model_comparison_ranking.csv"))

# Structural feature count for the 10 models built as extensions of Mk toward NT
# (Model 11 and Model 12 are deliberately excluded here -- they are negative
# controls on a different axis, state-count misspecification, not points on
# this structural-proximity scale, and are annotated separately below instead
# of being forced onto a feature count they don't really have).
feature_count <- tibble::tribble(
  ~modelID,   ~n_features, ~feature_label,
  "model1",   0,           "None (Mk baseline)",
  "model2",   1,           "+ACRV",
  "model3",   1,           "+Asymmetry",
  "model4",   1,           "+Partition",
  "model5",   2,           "+Partition+Asymmetry",
  "model6",   2,           "+Partition+ACRV",
  "model7",   3,           "+Partition+Asymmetry+ACRV (Gamma)",
  "model8",   3,           "+Partition+Asymmetry+ACRV (lognormal, NT)",
  "model9",   3,           "+Partition+Asymmetry+ACRV (free-rates)",
  "model10",  4,           "+Partition+Asymmetry+ACRV+free root"
)

plot_df <- ranking %>%
  filter(scenario == "nt") %>%
  inner_join(feature_count, by = "modelID") %>%
  mutate(model_label = recode(modelID,
    model1 = "M1", model2 = "M2", model3 = "M3", model4 = "M4",
    model5 = "M5", model6 = "M6", model7 = "M7", model8 = "M8 (NT)",
    model9 = "M9", model10 = "M10"))

# Negative controls, plotted as a separate reference layer rather than forced
# onto the x-axis scale, since they sit outside the NT structural-feature
# progression entirely.
neg_controls <- ranking %>%
  filter(scenario == "nt", modelID %in% c("model11", "model12")) %>%
  mutate(model_label = recode(modelID, model11 = "M11", model12 = "M12"))

p <- ggplot(plot_df, aes(x = n_features, y = median_cid)) +
  geom_smooth(method = "lm", se = TRUE, colour = "grey60", fill = "grey85", linewidth = 0.6) +
  geom_point(size = 3, colour = "#2C7FB8") +
  ggrepel::geom_text_repel(aes(label = model_label), size = 3.5, seed = 1) +
  geom_hline(data = neg_controls, aes(yintercept = median_cid, colour = model_label),
             linetype = "dashed", linewidth = 0.6) +
  scale_colour_manual(values = c("M11" = "#D95F02", "M12" = "#7570B3"),
                       name = "Negative controls\n(state-count misspecified,\nnot on this x-axis)") +
  scale_x_continuous(breaks = 0:4) +
  labs(
    title = "Structural proximity to NT vs tree accuracy (NT-generated data)",
    subtitle = "If proximity predicted accuracy, points would trend downward left-to-right.\nDashed lines show Model 11 / Model 12 for reference -- both outperform every point on the curve.",
    x = "Number of shared NT structural features",
    y = "Median CID (lower = more accurate)"
  ) +
  theme_minimal(base_size = 13) +
  theme(legend.position = "right", plot.subtitle = element_text(size = 10, colour = "grey30"))

ggsave(file.path(PATHS$fig_dir, "tree_accuracy", "25_structural_proximity_vs_accuracy.png"),
       p, width = 8, height = 5.5, dpi = 300)
