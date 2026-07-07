## ============================================================
## 04_imputation_accuracy_plots.R
## (renamed from 04_error_mse_plots.R: the pipeline reports imputation
## ACCURACY, not MSE, and has no bias/variance decomposition -- so
## this script is rebuilt around analysis/imputation_analysis.R's
## real outputs rather than a metric that doesn't exist in the data.
## Update run_all.R if you had the old filename hardcoded elsewhere.)
##
## Run:  Rscript viz/04_imputation_accuracy_plots.R
## Input: PATHS$imputation_rep (per-replicate) -- scenario, gridTag,
##        repID, modelID, acc_neo, acc_trans, mean_acc
##        PATHS$imputation_sum (grid-cell summary) -- adds n_reps + grid params
##        PATHS$imputation_wilcox -- pairwise Wilcoxon vs BASELINE_ID
##        (currently model1 for both scenarios, same caveat as script 03)
## ============================================================

source("viz/00_config_theme.R")

df <- safe_read_rds(PATHS$imputation_rep)
if (is.null(df)) quit(save = "no")

df <- df %>% label_models()

# ---------------------------------------------------------------
# PLOT 1: Imputation accuracy distribution by model/scenario
# Higher is better (proportion of correctly imputed states).
# ---------------------------------------------------------------
p1 <- ggplot(df, aes(x = modelID, y = mean_acc, fill = scenario)) +
  geom_boxplot(outlier.alpha = 0.3, width = 0.6, position = position_dodge(0.7)) +
  scale_fill_manual(values = SCENARIO_COLORS, name = "Generative scenario") +
  coord_flip() +
  labs(
    title = "Imputation accuracy by model",
    subtitle = "Higher is better. Mean of neo + trans partition accuracy per replicate.",
    x = NULL, y = "Mean imputation accuracy"
  )
save_fig(p1, "16_imputation_accuracy_by_model", height = 7)

# ---------------------------------------------------------------
# PLOT 2: Ranked bar chart (mean +/- SE) -- quick summary
# ---------------------------------------------------------------
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
save_fig(p2, "17_imputation_accuracy_ranked_bar", height = 7)

# ---------------------------------------------------------------
# PLOT 3: neo vs trans partition decomposition (the real analogue
# of a "which part of the signal is driving performance" plot --
## there's no bias/variance split in the pipeline, but there IS a
## neomorphic vs transformational character split).
# ---------------------------------------------------------------
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
save_fig(p3, "18_imputation_accuracy_by_partition", width = 9, height = 7)

# ---------------------------------------------------------------
# PLOT 4: Significance vs baseline (Wilcoxon results) -- how often
# is each model significantly better/worse/no-different from the
# baseline across grid cells? This complements the ranked-bar view
# with an explicit "how often does it actually win" read, rather
## than reducing everything to a single baseline-relative number.
# ---------------------------------------------------------------
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
        "Proportion of grid cells per outcome. NOTE: analysis/imputation_analysis.R currently ",
        "fixes BASELINE_ID = model1 for both scenarios -- see script 03's header for the same caveat."
      ),
      x = NULL, y = "Proportion of grid cells"
    )
  save_fig(p4, "19_imputation_significance_vs_baseline", width = 9, height = 7)
} else {
  message("imputation_wilcoxon.rds not found -- skipping plot 19 ",
          "(run analysis/imputation_analysis.R first).")
}

message("\n04_imputation_accuracy_plots.R complete -- figures written to ", PATHS$fig_dir)
