#!/bin/bash
# Run this from the ROOT of your local the-matrix clone:
#   bash reorganize_figures.sh
#
# Moves every existing flat figures/*.png / *.pdf into figures/<topic>/,
# matching the subfolders morphosim's save_fig() now writes into. Uses
# `git mv` so history is preserved. Safe to re-run -- files already in the
# right place are skipped (mv error is ignored).
#
# NOTE on the two dynamic-filename groups (tree_accuracy's "20_marginal_*"
# and model_comparison's "40_readable_table_nt_part_rate_*"): the exact set
# depends on your actual parameter grid values. The list below covers the
# standard grid (part_rate 1.00/2.50/5.00). If you have others, just
# `git mv figures/<name>.<ext> figures/<topic>/` for anything this script
# doesn't catch -- it prints anything left over in figures/ at the end.

set -e

declare -A TOPIC
TOPIC=(
  # tree_accuracy
  [01_cid_by_model_scenario]=tree_accuracy
  [02_delta_cid_vs_scenario_baseline]=tree_accuracy
  [03_model_ranking_heatmap]=tree_accuracy
  [04_cid_distribution_detail]=tree_accuracy
  [05_grid_cell_win_counts]=tree_accuracy
  [20_marginal_tree_length_by_model]=tree_accuracy
  [20_marginal_gain_loss_by_model]=tree_accuracy
  [20_marginal_n_char_by_model]=tree_accuracy
  [21_marginal_part_rate_by_model_nt]=tree_accuracy
  [24_parameter_sensitivity_summary]=tree_accuracy
  [25_win_region_tree_length_gain_loss]=tree_accuracy
  [26_tree_similarity_heatmap_mk]=tree_accuracy
  [27_tree_similarity_heatmap_nt_by_part_rate]=tree_accuracy
  [28_best_model_per_cell_mk]=tree_accuracy
  [29_best_model_per_cell_nt_by_part_rate]=tree_accuracy
  [30_best_worst_model_gridcell_combos]=tree_accuracy

  # convergence
  [06_convergence_pass_rate_heatmap]=convergence
  [07_rhat_by_model]=convergence
  [08_ess_by_model]=convergence
  [09_asdsf_by_model]=convergence
  [10_tree_ess_vs_scalar_ess]=convergence
  [11_convergence_vs_accuracy]=convergence

  # gam_threshold
  [12_threshold_crossing_vs_scenario_baseline]=gam_threshold
  [13_threshold_heatmap_vs_scenario_baseline]=gam_threshold
  [14_improvement_vs_scenario_baseline]=gam_threshold
  [15_threshold_crossing_vs_scenario_baseline]=gam_threshold

  # cross_metric
  [16_rank_concordance_bump_chart]=cross_metric
  [17_composite_scorecard_heatmap]=cross_metric
  [18_model_scatter_cid_vs_known_answer_mse]=cross_metric
  [19_gridcell_cid_vs_known_answer_mse_by_model]=cross_metric

  # model_comparison
  [31_overall_model_ranking]=model_comparison
  [32_main_effect_tree_length]=model_comparison
  [33_main_effect_gain_loss]=model_comparison
  [34_main_effect_n_char]=model_comparison
  [35_main_effect_part_rate_nt]=model_comparison
  [36_mk_vs_nt_scatter]=model_comparison
  [37_mk_vs_nt_win_rate]=model_comparison
  [38_best_combo_per_model]=model_comparison
  [39_readable_table_mk]=model_comparison
  [40_readable_table_nt_part_rate_1_00]=model_comparison
  [40_readable_table_nt_part_rate_2_50]=model_comparison
  [40_readable_table_nt_part_rate_5_00]=model_comparison

  # dashboard (cross-cutting, doesn't belong to one topic)
  [00_summary_dashboard]=dashboard
)

for name in "${!TOPIC[@]}"; do
  topic="${TOPIC[$name]}"
  mkdir -p "figures/$topic"
  for ext in png pdf; do
    if [ -f "figures/${name}.${ext}" ]; then
      git mv "figures/${name}.${ext}" "figures/${topic}/${name}.${ext}"
      echo "moved figures/${name}.${ext} -> figures/${topic}/"
    fi
  done
done

echo ""
echo "Left in figures/ root (not auto-matched -- move these by hand):"
find figures -maxdepth 1 -type f \( -name "*.png" -o -name "*.pdf" \)

echo ""
echo "known_answer/ figures were already in their own subfolder -- untouched."
echo ""
echo "Review with 'git status', then:"
echo "  git commit -m \"Reorganize figures into topic subfolders\""
echo "  git push origin <branch>"
