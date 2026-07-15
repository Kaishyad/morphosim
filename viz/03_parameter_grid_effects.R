# 03_parameter_grid_effects.R

source("viz/00_config_theme.R")

predictors <- c("tree_length", "rate_ratio", "chars_per_taxon")

# (A) Pipeline's own threshold summaries (baseline = model1 always)
thresh_mk <- safe_read_rds(PATHS$threshold_mk)
thresh_nt <- safe_read_rds(PATHS$threshold_nt)
thresh_df <- bind_rows(thresh_mk, thresh_nt)

if (!is.null(thresh_df) && nrow(thresh_df) > 0L) {
  thresh_df <- thresh_df %>% filter(!is.na(threshold)) %>% label_models()

  p1 <- ggplot(thresh_df, aes(x = threshold, y = modelID, color = scenario)) +
    geom_point(size = 3) +
    facet_wrap(~ predictor, scales = "free_x") +
    scale_color_manual(values = SCENARIO_COLORS, name = "Generative scenario") +
    labs(
      title = "GAM threshold: predictor value where each model crosses zero improvement over its scenario baseline",
      subtitle = "mk models vs model1 (Mk baseline); nt models vs model8 (NT baseline) -- from run/gam_threshold.R",
      x = "Predictor value at zero-crossing", y = NULL
    )
  save_fig(p1, "12_threshold_crossing_vs_scenario_baseline", width = 10, height = 6)

  p2 <- ggplot(thresh_df, aes(x = predictor, y = fct_rev(modelID), fill = threshold)) +
    geom_tile(color = "white", linewidth = 0.8) +
    geom_text(aes(label = sprintf("%.2f", threshold)), size = 3) +
    scale_fill_viridis_c(option = "cividis", name = "Threshold") +
    facet_wrap(~ scenario) +
    labs(
      title = "Threshold values across the full predictor grid (vs scenario baseline)",
      x = "Predictor", y = NULL
    ) +
    theme(panel.grid = element_blank(), axis.text.x = element_text(angle = 40, hjust = 1))
  save_fig(p2, "13_threshold_heatmap_vs_scenario_baseline", width = 9, height = 7)
} else {
  message("threshold_summary_{mk,nt}.rds not found -- skipping plots 12/13 ",
          "(run run/gam_threshold.R first).")
}

# (B) Scenario-correct baseline comparison, computed here directly:
cid_data <- safe_read_rds(PATHS$tree_accuracy_rep)

if (!is.null(cid_data)) {
  build_improvement <- function(scenario, baseline_id) {
    sub_base <- cid_data %>%
      filter(scenario == !!scenario, modelID == baseline_id) %>%
      select(repID, gridTag, cid_base = median_cid)

    sub_eval <- cid_data %>%
      filter(scenario == !!scenario, modelID != baseline_id)

    grid          <- ScenarioGrid(scenario)
    grid$gridTag  <- vapply(seq_len(nrow(grid)), function(i) GridTag(as.list(grid[i, ])), character(1))
    grid_cols     <- grid[, intersect(c("tree_length", "gain_loss", "n_char", "n_taxa", "gridTag"), names(grid))]

    sub_eval %>%
      inner_join(sub_base, by = c("repID", "gridTag")) %>%
      mutate(improvement = cid_base - median_cid) %>%   # positive = better than scenario baseline
      left_join(grid_cols, by = "gridTag") %>%
      mutate(
        rate_ratio      = gain_loss,
        chars_per_taxon = n_char / n_taxa,
        baseline_id     = baseline_id
      )
  }

  improvement_df <- bind_rows(
    build_improvement("mk", BASELINE_BY_SCENARIO[["mk"]]),
    build_improvement("nt", BASELINE_BY_SCENARIO[["nt"]])
  ) %>%
    label_models()

  improvement_long <- improvement_df %>%
    pivot_longer(all_of(predictors), names_to = "predictor", values_to = "pred_value")

  p3 <- ggplot(improvement_long, aes(x = pred_value, y = improvement, color = modelID)) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "grey40") +
    geom_smooth(method = "gam", formula = y ~ s(x, bs = "cs"), se = TRUE, linewidth = 0.8, alpha = 0.12) +
    facet_grid(scenario ~ predictor, scales = "free_x") +
    scale_color_manual(values = setNames(model_palette(length(unique(improvement_long$modelID))),
                                          levels(improvement_long$modelID)),
                        name = NULL) +
    labs(
      title = "Improvement over each scenario's own baseline",
      subtitle = paste0(
        "mk models vs ", MODEL_LABELS[["model1"]], " (top row)  |  nt models vs ", MODEL_LABELS[["model8"]], " (bottom row). ",
        "Above the dashed line = better than that scenario's baseline."
      ),
      x = "Predictor value", y = expression("Improvement over scenario baseline ("*Delta*" CID)")
    )
  save_fig(p3, "14_improvement_vs_scenario_baseline", width = 11, height = 7)

# Zero-crossing per model/predictor/scenario, linear interpolation
  find_crossing <- function(x, y) {
    o <- order(x); x <- x[o]; y <- y[o]
    sign_change <- which(diff(sign(y)) != 0)
    if (length(sign_change) == 0) return(NA_real_)
    i <- sign_change[1]
    x[i] + (0 - y[i]) * (x[i + 1] - x[i]) / (y[i + 1] - y[i])
  }

  crossings <- improvement_long %>%
    group_by(modelID, scenario, predictor) %>%
    summarise(threshold = find_crossing(pred_value, improvement), .groups = "drop") %>%
    filter(!is.na(threshold))

  if (nrow(crossings) > 0L) {
    p4 <- ggplot(crossings, aes(x = threshold, y = modelID, color = scenario)) +
      geom_point(size = 3) +
      facet_wrap(~ predictor, scales = "free_x") +
      scale_color_manual(values = SCENARIO_COLORS, name = "Generative scenario") +
      labs(
        title = "Threshold vs each scenario's own baseline",
        subtitle = "mk vs model1, nt vs model8 -- linear interpolation to zero improvement",
        x = "Predictor value at zero-crossing", y = NULL
      )
    save_fig(p4, "15_threshold_crossing_vs_scenario_baseline", width = 10, height = 6)
  }
} else {
  message("tree_accuracy_per_rep.rds not found -- skipping plots 14/15 ",
          "(run run/tree_accuracy.R first).")
}

message("\n03_parameter_grid_effects.R complete -- figures written to ", PATHS$fig_dir)
