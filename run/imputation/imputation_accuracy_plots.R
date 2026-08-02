# imputation_accuracy_plots.R

source("run/shared/config_theme.R")

df <- safe_read_rds(PATHS$imputation_rep)
if (is.null(df)) quit(save = "no")

df <- df %>% label_models()

# PLOT 1: Imputation accuracy distribution by model/scenario
p1 <- ggplot(df, aes(x = modelID, y = mean_acc, fill = scenario)) +
  geom_boxplot(outlier.alpha = 0.3, width = 0.6, position = position_dodge(0.7)) +
  scale_fill_manual(values = SCENARIO_COLORS, name = "Generative scenario") +
  coord_flip() +
  labs(
    title = "Imputation accuracy by model",
    subtitle = "Higher is better. Mean of neo + trans partition accuracy per replicate.",
    x = NULL, y = "Mean imputation accuracy"
  )
save_fig(p1, "16_imputation_accuracy_by_model", subdir = "imputation", height = 7)

# PLOT 2: Ranked bar chart (mean +/- SE) -- quick summary
summary_df <- df %>%
  group_by(modelID, scenario) %>%
  summarise(mean_of_mean_acc = mean(mean_acc, na.rm = TRUE),
            se_acc = sd(mean_acc, na.rm = TRUE) / sqrt(n()), .groups = "drop")

p2 <- ggplot(summary_df, aes(x = fct_reorder(modelID, mean_of_mean_acc), y = mean_of_mean_acc, fill = scenario)) +
  geom_col(position = position_dodge(0.75), width = 0.65) +
  geom_errorbar(aes(ymin = mean_of_mean_acc - se_acc, ymax = mean_of_mean_acc + se_acc),
                position = position_dodge(0.75), width = 0.2) +
  scale_fill_manual(values = SCENARIO_COLORS, name = "Generative scenario") +
  coord_flip() +
  labs(
    title = "Mean imputation accuracy ranked (best to worst)",
    subtitle = "Error bars = standard error across grid cells / replicates",
    x = NULL, y = "Mean imputation accuracy"
  )
save_fig(p2, "17_imputation_accuracy_ranked_bar", subdir = "imputation", height = 7)

# PLOT 3: neo vs trans partition decomposition (the real analogue
part_long <- df %>%
  select(modelID, scenario, repID, gridTag, acc_neo, acc_trans) %>%
  pivot_longer(c(acc_neo, acc_trans), names_to = "partition", values_to = "accuracy") %>%
  mutate(partition = recode(partition, acc_neo = "neomorphic", acc_trans = "transformational"))

p3 <- ggplot(part_long, aes(x = modelID, y = accuracy, fill = partition)) +
  geom_col(position = "dodge", stat = "summary", fun = "mean") +
  facet_wrap(~ scenario) +
  scale_fill_manual(values = c(neomorphic = "#D95F02", transformational = "#7570B3"), name = NULL) +
  coord_flip() +
  labs(
    title = "Imputation accuracy by character partition",
    subtitle = "Mean accuracy for neomorphic vs transformational characters, by model",
    x = NULL, y = "Mean accuracy"
  )
save_fig(p3, "18_imputation_accuracy_by_partition", subdir = "imputation", width = 9, height = 7)

# PLOT 4: Significance vs baseline (Wilcoxon results) -- how often
wilcox_df <- safe_read_rds(PATHS$imputation_wilcox)

if (!is.null(wilcox_df)) {
  wilcox_df <- wilcox_df %>%
    mutate(
      call = case_when(
        !is.na(p.adj) & p.adj < 0.05 & direction == "better" ~ "significantly better",
        !is.na(p.adj) & p.adj < 0.05 & direction == "worse"  ~ "significantly worse",
        !is.na(p.adj) ~ "no significant difference",
        TRUE ~ NA_character_
      )
    ) %>%
    filter(!is.na(call)) %>%
    label_models()

  call_counts <- wilcox_df %>%
    count(scenario, modelID, call) %>%
    group_by(scenario, modelID) %>%
    mutate(prop = n / sum(n)) %>%
    ungroup()

  p4 <- ggplot(call_counts, aes(x = modelID, y = prop, fill = call)) +
    geom_col(position = "stack", width = 0.65) +
    facet_wrap(~ scenario) +
    scale_y_continuous(labels = percent) +
    scale_fill_manual(values = c(
      "significantly better"       = "#1A9850",
      "no significant difference"  = "#FEE08B",
      "significantly worse"        = "#B2182B"
    ), name = NULL) +
    coord_flip() +
    labs(
      title = "How often does each model beat its baseline? (Wilcoxon, BH-adjusted p < 0.05)",
      subtitle = paste0(
        "Proportion of grid cells per outcome. Baseline is model1 for mk and model8 for nt ",
        "(run/imputation/imputation_analysis.R -- fixed to match the rest of the pipeline)."
      ),
      x = NULL, y = "Proportion of grid cells"
    )
  save_fig(p4, "19_imputation_significance_vs_baseline", subdir = "imputation", width = 9, height = 7)
} else {
  message("imputation_wilcoxon.rds not found -- skipping plot 19 ",
          "(run run/imputation/imputation_analysis.R first).")
}

message("\nimputation_accuracy_plots.R complete -- figures written to ", PATHS$fig_dir)
