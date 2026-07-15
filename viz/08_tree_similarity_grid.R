# 08_tree_similarity_grid.R

source("viz/00_config_theme.R")

sum_df <- safe_read_rds(PATHS$tree_accuracy_sum)
if (is.null(sum_df)) quit(save = "no")

sum_df <- sum_df %>% filter(!is.na(median_cid))

sum_df$cell_label <- sprintf("TL=%.1f  GL=%.2f  NC=%d",
                             sum_df$tree_length, sum_df$gain_loss, sum_df$n_char)

# Order models best-to-worst by mean CID (pooled across scenarios), used
model_order <- sum_df %>%
  group_by(modelID) %>%
  summarise(mean_cid = mean(median_cid, na.rm = TRUE), .groups = "drop") %>%
  arrange(mean_cid) %>%
  pull(modelID)

sum_df <- sum_df %>%
  mutate(modelID = factor(modelID, levels = model_order, labels = MODEL_LABELS[model_order]))

mk_df <- sum_df %>% filter(scenario == "mk")
nt_df <- sum_df %>% filter(scenario == "nt")

# Heatmap: every grid cell x every model, coloured by median CID.
.HeatmapCells <- function(df, facet_by_part_rate = FALSE) {
  df <- df %>%
    arrange(tree_length, gain_loss, n_char) %>%
    mutate(cell_label = fct_inorder(cell_label))

  p <- ggplot(df, aes(x = modelID, y = cell_label, fill = median_cid)) +
    geom_tile(color = "white", linewidth = 0.15) +
    scale_fill_viridis_c(option = "viridis", direction = -1, name = "Median CID\n(lower = better)") +
    labs(x = NULL, y = "tree_length / gain_loss / n_char") +
    theme(axis.text.x = element_text(angle = 45, hjust = 1),
         axis.text.y = element_text(size = rel(0.55)),
         panel.grid = element_blank())

  if (facet_by_part_rate) {
    p <- p + facet_wrap(~ part_rate, ncol = 3,
                        labeller = labeller(part_rate = function(x) paste("part_rate =", x)))
  }
  p
}

if (nrow(mk_df) > 0L) {
  p1 <- .HeatmapCells(mk_df) +
    labs(title = "Tree accuracy by model and parameter combination -- mk",
        subtitle = "Read down a column to compare parameters for one model; read across a row to compare models for one combination.")
  save_fig(p1, "26_tree_similarity_heatmap_mk", width = 9, height = 12)
}

if (nrow(nt_df) > 0L) {
  p2 <- .HeatmapCells(nt_df, facet_by_part_rate = TRUE) +
    labs(title = "Tree accuracy by model and parameter combination -- nt",
        subtitle = "Split into 3 panels by part_rate.")
  save_fig(p2, "27_tree_similarity_heatmap_nt_by_part_rate", width = 20, height = 12)
}

# Best model per grid cell -- which model wins where.
.BestModelPerCell <- function(df) {
  df %>%
    group_by(scenario, gridTag, cell_label, tree_length, gain_loss, n_char,
             across(any_of("part_rate"))) %>%
    slice_min(median_cid, n = 1, with_ties = FALSE) %>%
    ungroup()
}

best_mk <- .BestModelPerCell(mk_df)
best_nt <- .BestModelPerCell(nt_df)

model_colors <- setNames(model_palette(length(model_order)), MODEL_LABELS[model_order])

if (nrow(best_mk) > 0L) {
  p3 <- best_mk %>%
    arrange(tree_length, gain_loss, n_char) %>%
    mutate(cell_label = fct_inorder(cell_label)) %>%
    ggplot(aes(x = 1, y = cell_label, fill = modelID)) +
    geom_tile(color = "white") +
    scale_fill_manual(values = model_colors, name = "Best model") +
    labs(title = "Best model per parameter combination -- mk",
        x = NULL, y = "tree_length / gain_loss / n_char") +
    theme(axis.text.x = element_blank(), axis.text.y = element_text(size = rel(0.55)),
         panel.grid = element_blank())
  save_fig(p3, "28_best_model_per_cell_mk", width = 6, height = 12)
}

if (nrow(best_nt) > 0L) {
  p4 <- best_nt %>%
    arrange(tree_length, gain_loss, n_char) %>%
    mutate(cell_label = fct_inorder(cell_label)) %>%
    ggplot(aes(x = 1, y = cell_label, fill = modelID)) +
    geom_tile(color = "white") +
    scale_fill_manual(values = model_colors, name = "Best model") +
    facet_wrap(~ part_rate, ncol = 3,
              labeller = labeller(part_rate = function(x) paste("part_rate =", x))) +
    labs(title = "Best model per parameter combination -- nt",
        x = NULL, y = "tree_length / gain_loss / n_char") +
    theme(axis.text.x = element_blank(), axis.text.y = element_text(size = rel(0.55)),
         panel.grid = element_blank())
  save_fig(p4, "29_best_model_per_cell_nt_by_part_rate", width = 14, height = 12)
}

# Top/bottom 10 (model, parameter combination) pairs per scenario.
extremes <- sum_df %>%
  group_by(scenario) %>%
  group_modify(~ bind_rows(
    slice_min(.x, median_cid, n = 10) %>% mutate(group = "10 closest to true tree"),
    slice_max(.x, median_cid, n = 10) %>% mutate(group = "10 furthest from true tree")
  )) %>%
  ungroup() %>%
  mutate(row_label = paste0(as.character(modelID), " | ", cell_label))

if (nrow(extremes) > 0L) {
  p5 <- ggplot(extremes, aes(x = median_cid, y = fct_reorder(row_label, median_cid), color = group)) +
    geom_point(size = 2.5) +
    scale_color_manual(values = c("10 closest to true tree" = "#2C7FB8",
                                  "10 furthest from true tree" = "#D95F02"), name = NULL) +
    facet_wrap(~ scenario, scales = "free", ncol = 1) +
    labs(title = "Best and worst (model, parameter combination) pairs",
        x = "Median CID (lower = closer to true tree)", y = NULL) +
    theme(axis.text.y = element_text(size = rel(0.7)))
  save_fig(p5, "30_best_worst_model_gridcell_combos", width = 11, height = 10)
}

# Tables. Long CSV for filtering/pivoting yourself, plus a wide table
export_cols <- intersect(c("scenario", "modelID", "gridTag", "tree_length", "gain_loss",
                           "n_char", "part_rate", "median_cid", "iqr_cid", "n_reps"),
                         colnames(sum_df))
long_out <- sum_df
long_out$modelID <- as.character(long_out$modelID)
readr::write_csv(long_out[, export_cols], file.path(PATHS$results_dir, "tree_similarity_table_long.csv"))

.WideTable <- function(df, param_cols) {
  df %>%
    select(all_of(param_cols), modelID, median_cid) %>%
    mutate(modelID = as.character(modelID)) %>%
    pivot_wider(names_from = modelID, values_from = median_cid) %>%
    arrange(across(all_of(param_cols)))
}

if (nrow(mk_df) > 0L) {
  wide_mk <- .WideTable(mk_df, c("tree_length", "gain_loss", "n_char"))
  readr::write_csv(wide_mk, file.path(PATHS$results_dir, "tree_similarity_table_wide_mk.csv"))
}

if (nrow(nt_df) > 0L) {
  wide_nt <- .WideTable(nt_df, c("tree_length", "gain_loss", "n_char", "part_rate"))
  readr::write_csv(wide_nt, file.path(PATHS$results_dir, "tree_similarity_table_wide_nt.csv"))
}

message("Saved tree_similarity_table_long.csv and tree_similarity_table_wide_{mk,nt}.csv to ", PATHS$results_dir)
message("08_tree_similarity_grid.R complete -- figures written to ", PATHS$fig_dir)
