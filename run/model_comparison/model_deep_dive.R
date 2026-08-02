# model_deep_dive.R

source("run/shared/config_theme.R")

sum_df <- safe_read_rds(PATHS$tree_accuracy_sum)
if (is.null(sum_df)) quit(save = "no")

sum_df <- sum_df %>% filter(!is.na(median_cid))

# Sanity check: which models are actually present. This is printed
present <- sum_df %>%
  distinct(scenario, modelID) %>%
  arrange(scenario, modelID)
message("Models present in tree_accuracy_sum, by scenario:")
for (s in unique(present$scenario)) {
  mods <- present$modelID[present$scenario == s]
  message(sprintf("  %s (%d models): %s", s, length(mods), paste(sort(mods), collapse = ", ")))
}
message("If a model you expect is missing above, this script cannot show it -- ",
       "re-run the upstream summarisation step for that model first.")

# Best-to-worst model order, pooled across scenarios (same convention as 08)
model_order <- sum_df %>%
  group_by(modelID) %>%
  summarise(mean_cid = mean(median_cid, na.rm = TRUE), .groups = "drop") %>%
  arrange(mean_cid) %>%
  pull(modelID)

sum_df <- sum_df %>%
  mutate(modelID_label = factor(modelID, levels = model_order, labels = MODEL_LABELS[model_order]))

model_colors <- setNames(model_palette(length(model_order)), MODEL_LABELS[model_order])

mk_df <- sum_df %>% filter(scenario == "mk")
nt_df <- sum_df %>% filter(scenario == "nt")

# 1. OVERALL RANKING -- every model, both scenarios, full spread
p_rank <- ggplot(sum_df, aes(x = modelID_label, y = median_cid, fill = modelID_label)) +
  geom_boxplot(outlier.size = 0.8, alpha = 0.85) +
  stat_summary(fun = mean, geom = "point", shape = 23, size = 2, fill = "white") +
  scale_fill_manual(values = model_colors, guide = "none") +
  facet_wrap(~ scenario, ncol = 1, scales = "free_x") +
  labs(title = "Overall model ranking across the full parameter grid",
      subtitle = "Diamond = mean; box = spread across all parameter combinations and reps. Models ordered best-to-worst (pooled).",
      x = NULL, y = "Median CID (lower = closer to true tree)") +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))
save_fig(p_rank, "31_overall_model_ranking", subdir = "model_comparison", width = 12, height = 9)

# 2. PARAMETER MAIN EFFECTS -- what actually differentiates models.
.MainEffectPlot <- function(param, param_label) {
  df <- sum_df %>%
    group_by(scenario, modelID_label, .data[[param]]) %>%
    summarise(mean_cid = mean(median_cid, na.rm = TRUE), .groups = "drop")

  ggplot(df, aes(x = .data[[param]], y = mean_cid, color = modelID_label, group = modelID_label)) +
    geom_line(linewidth = 0.9, alpha = 0.85) +
    geom_point(size = 1.8) +
    scale_color_manual(values = model_colors, name = "Model") +
    facet_wrap(~ scenario, scales = "free_y") +
    labs(title = paste("Effect of", param_label, "on tree accuracy, by model"),
        x = param_label, y = "Mean of median CID (lower = better)")
}

p_tl <- .MainEffectPlot("tree_length", "tree length")
save_fig(p_tl, "32_main_effect_tree_length", subdir = "model_comparison", width = 13, height = 7)

p_gl <- .MainEffectPlot("gain_loss", "gain-to-loss ratio")
save_fig(p_gl, "33_main_effect_gain_loss", subdir = "model_comparison", width = 13, height = 7)

p_nc <- .MainEffectPlot("n_char", "character count")
save_fig(p_nc, "34_main_effect_n_char", subdir = "model_comparison", width = 13, height = 7)

if ("part_rate" %in% colnames(nt_df) && nrow(nt_df) > 0L) {
  p_pr <- nt_df %>%
    group_by(modelID_label, part_rate) %>%
    summarise(mean_cid = mean(median_cid, na.rm = TRUE), .groups = "drop") %>%
    ggplot(aes(x = factor(part_rate), y = mean_cid, color = modelID_label, group = modelID_label)) +
    geom_line(linewidth = 0.9, alpha = 0.85) +
    geom_point(size = 1.8) +
    scale_color_manual(values = model_colors, name = "Model") +
    labs(title = "Effect of partition rate scalar on tree accuracy, by model (nt only)",
        x = "Partition rate scalar", y = "Mean of median CID (lower = better)")
  save_fig(p_pr, "35_main_effect_part_rate_nt", subdir = "model_comparison", width = 11, height = 7)
}

# 3. MK vs NT -- does going NT actually help, model by model?
nt_avg <- nt_df %>%
  group_by(modelID, modelID_label, tree_length, gain_loss, n_char) %>%
  summarise(median_cid_nt = mean(median_cid, na.rm = TRUE), .groups = "drop")

mk_join <- mk_df %>%
  select(modelID, modelID_label, tree_length, gain_loss, n_char, median_cid_mk = median_cid)

mk_vs_nt <- inner_join(mk_join, nt_avg, by = c("modelID", "modelID_label", "tree_length", "gain_loss", "n_char")) %>%
  mutate(nt_improves = median_cid_nt < median_cid_mk)

if (nrow(mk_vs_nt) > 0L) {
  axis_max <- max(mk_vs_nt$median_cid_mk, mk_vs_nt$median_cid_nt, na.rm = TRUE)

  p_scatter <- ggplot(mk_vs_nt, aes(x = median_cid_mk, y = median_cid_nt, color = modelID_label)) +
    geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "grey50") +
    geom_point(alpha = 0.7, size = 2) +
    scale_color_manual(values = model_colors, name = "Model") +
    coord_equal(xlim = c(0, axis_max), ylim = c(0, axis_max)) +
    labs(title = "Does the NT model actually beat Mk for the same parameters?",
        subtitle = "Points below the dashed line = NT closer to the true tree than Mk for that combination.",
        x = "Median CID -- Mk", y = "Median CID -- NT (averaged over part_rate)")
  save_fig(p_scatter, "36_mk_vs_nt_scatter", subdir = "model_comparison", width = 9, height = 9)

  p_summary <- mk_vs_nt %>%
    group_by(modelID_label) %>%
    summarise(pct_nt_improves = 100 * mean(nt_improves), .groups = "drop") %>%
    ggplot(aes(x = fct_reorder(modelID_label, pct_nt_improves), y = pct_nt_improves, fill = modelID_label)) +
    geom_col(alpha = 0.9) +
    geom_hline(yintercept = 50, linetype = "dashed", color = "grey40") +
    scale_fill_manual(values = model_colors, guide = "none") +
    coord_flip() +
    labs(title = "Share of parameter combinations where NT beats Mk, by model",
        subtitle = "Dashed line = 50% (coin-flip). Above it, NT wins more often than not for that model.",
        x = NULL, y = "% of parameter combinations where NT < Mk median CID")
  save_fig(p_summary, "37_mk_vs_nt_win_rate", subdir = "model_comparison", width = 10, height = 7)
}

# 4. BEST PARAMETER COMBINATION PER MODEL -- one row per model,
best_combo_per_model <- sum_df %>%
  group_by(scenario, modelID_label) %>%
  slice_min(median_cid, n = 1, with_ties = FALSE) %>%
  ungroup() %>%
  mutate(combo_label = sprintf("TL=%.1f, GL=%.2f, NC=%d%s",
                               tree_length, gain_loss, n_char,
                               if ("part_rate" %in% colnames(.)) ifelse(is.na(part_rate), "", sprintf(", PR=%.2f", part_rate)) else ""))

p_best_combo <- ggplot(best_combo_per_model,
                       aes(x = median_cid, y = fct_reorder(modelID_label, median_cid, .desc = TRUE))) +
  geom_col(aes(fill = modelID_label), alpha = 0.9, width = 0.6) +
  geom_text(aes(label = combo_label), hjust = -0.05, size = 3) +
  scale_fill_manual(values = model_colors, guide = "none") +
  facet_wrap(~ scenario, ncol = 1, scales = "free_y") +
  xlim(0, max(best_combo_per_model$median_cid, na.rm = TRUE) * 1.6) +
  labs(title = "Each model's single best parameter combination",
      subtitle = "Bar = that model's lowest achievable median CID; label = the exact parameter combination it came from.",
      x = "Median CID at best combination", y = NULL)
save_fig(p_best_combo, "38_best_combo_per_model", subdir = "model_comparison", width = 12, height = 9)

readr::write_csv(
  best_combo_per_model %>%
    select(scenario, model = modelID_label, tree_length, gain_loss, n_char, any_of("part_rate"), median_cid, combo_label),
  file.path(PATHS$results_dir, "best_combo_per_model.csv")
)

# 5. READABLE TABLES -- numbers overlaid on a heatmap (sorted,
.ReadableTable <- function(df, param_cols, title, filename, width, height, subdir = "model_comparison") {
  df <- df %>%
    mutate(cell_label = do.call(paste, c(lapply(param_cols, function(p) sprintf("%s=%s", p, df[[p]])), sep = ", ")))

  # Row order: FIX -- best (lowest mean CID = most accurate) at top, worst at
  # bottom, matching the subtitle below. (ggplot puts factor level 1 at the
  # bottom of a discrete y-axis, so "best first" needs a DESCENDING sort here
  # to land best at the top.)
  row_order <- df %>%
    group_by(cell_label) %>%
    summarise(row_mean = mean(median_cid, na.rm = TRUE), .groups = "drop") %>%
    arrange(desc(row_mean)) %>%
    pull(cell_label)

  # Column order: FIX -- computed from THIS table's own data only, not the
  # single pooled ranking shared across every table (which was why every
  # mk/nt/part_rate table showed the same model order regardless of what its
  # own numbers said).
  col_order <- df %>%
    group_by(modelID_label) %>%
    summarise(model_mean = mean(median_cid, na.rm = TRUE), .groups = "drop") %>%
    arrange(model_mean) %>%
    pull(modelID_label)

  df <- df %>%
    mutate(cell_label = factor(cell_label, levels = row_order),
          modelID_label = factor(modelID_label, levels = col_order))

  p <- ggplot(df, aes(x = modelID_label, y = cell_label, fill = median_cid)) +
    geom_tile(color = "white", linewidth = 0.3) +
    geom_text(aes(label = sprintf("%.3f", median_cid)), size = 2.4, color = "black") +
    scale_fill_viridis_c(option = "viridis", direction = -1, name = "Median CID") +
    labs(title = title, x = NULL, y = NULL,
        subtitle = "Rows sorted best (top) to worst (bottom); columns sorted best (left) to worst (right), both for this table's own data.") +
    theme(axis.text.x = element_text(angle = 45, hjust = 1),
         axis.text.y = element_text(size = rel(0.6)),
         panel.grid = element_blank())
  save_fig(p, filename, subdir = subdir, width = width, height = height)

# Clean, sorted, rounded CSV to accompany the figure
  wide_clean <- df %>%
    select(cell_label, modelID_label, median_cid) %>%
    mutate(median_cid = round(median_cid, 3)) %>%
    pivot_wider(names_from = modelID_label, values_from = median_cid) %>%
    arrange(match(cell_label, row_order))
  readr::write_csv(wide_clean, file.path(PATHS$results_dir, paste0(filename, ".csv")))
}

if (nrow(mk_df) > 0L) {
  .ReadableTable(mk_df, c("tree_length", "gain_loss", "n_char"),
                "Tree accuracy, mk -- readable table (sorted + rounded)",
                "39_readable_table_mk", width = 10, height = 12)
}

if (nrow(nt_df) > 0L) {
  for (pr in sort(unique(nt_df$part_rate))) {
    sub <- nt_df %>% filter(part_rate == pr)
    if (nrow(sub) == 0L) next
    .ReadableTable(sub, c("tree_length", "gain_loss", "n_char"),
                  sprintf("Tree accuracy, nt (part_rate = %.2f) -- readable table", pr),
                  sprintf("40_readable_table_nt_part_rate_%s", gsub("\\.", "_", sprintf("%.2f", pr))),
                  width = 10, height = 10)
  }
}

# 6. FINER READABLE TABLES -- same idea but split further by n_char too, so
# each table only has tree_length x gain_loss as rows (16 rows instead of
# ~60). Saved in their own subfolder since there are a lot of them.
if (nrow(mk_df) > 0L) {
  for (nc in sort(unique(mk_df$n_char))) {
    sub <- mk_df %>% filter(n_char == nc)
    if (nrow(sub) == 0L) next
    .ReadableTable(sub, c("tree_length", "gain_loss"),
                  sprintf("Tree accuracy, mk (n_char = %d) -- readable table", nc),
                  sprintf("readable_table_mk_n_char_%d", nc),
                  width = 8, height = 6, subdir = "model_comparison/readable_tables")
  }
}

if (nrow(nt_df) > 0L) {
  for (pr in sort(unique(nt_df$part_rate))) {
    for (nc in sort(unique(nt_df$n_char))) {
      sub <- nt_df %>% filter(part_rate == pr, n_char == nc)
      if (nrow(sub) == 0L) next
      .ReadableTable(sub, c("tree_length", "gain_loss"),
                    sprintf("Tree accuracy, nt (part_rate = %.2f, n_char = %d) -- readable table", pr, nc),
                    sprintf("readable_table_nt_part_rate_%s_n_char_%d",
                            gsub("\\.", "_", sprintf("%.2f", pr)), nc),
                    width = 8, height = 6, subdir = "model_comparison/readable_tables")
    }
  }
}

message("\nmodel_deep_dive.R complete -- figures written to ", PATHS$fig_dir,
       ", tables written to ", PATHS$results_dir)
