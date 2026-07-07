# Driver for R/analysis/ModelComparison.R -- the "how do all models compare
# to each other" and "how does each model compare to itself across
# scenarios" analyses that ThresholdGAM.R doesn't answer on its own.
#
# Usage:
#   Rscript run/model_comparison.R
#
# Requires: results/tree_accuracy_per_rep.rds (from run/tree_accuracy.R)
# already populated for the models/scenarios you want included. Models
# with incomplete data are automatically dropped from AllModelsComparison
# with a warning (see ModelComparison.R) rather than silently skewing it.

source("R/core/_setup.R")
source("R/analysis/ModelComparison.R")

cid_rds <- file.path(OutputDir(), "results", "tree_accuracy_per_rep.rds")
if (!file.exists(cid_rds)) {
  stop("Tree accuracy data not found: ", cid_rds,
       "\nRun run/tree_accuracy.R (and merge_tree_accuracy.R) first.")
}
cid_data <- readRDS(cid_rds)

out_dir <- file.path(OutputDir(), "results")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# --- Safety: work only with models that actually have data ----------------
# model7/model9 (or any other model) may currently have zero rows -- e.g.
# while awaiting reruns. Rather than looping the full MODEL_IDS and letting
# empty-data errors propagate, derive the working model list from what's
# actually present in cid_data, and report what got excluded so it's
# obvious in the log rather than a silent gap in the output tables.
PRESENT_MODELS <- sort(unique(cid_data$modelID))
MISSING_MODELS <- setdiff(MODEL_IDS, PRESENT_MODELS)

if (length(MISSING_MODELS) > 0L) {
  cli::cli_alert_warning(
    "No tree-accuracy data at all for: {paste(MISSING_MODELS, collapse = ', ')} -- excluded from every table below."
  )
}
if (length(PRESENT_MODELS) < 2L) {
  stop("Fewer than 2 models have any data -- nothing to compare. ",
       "Run run/tree_accuracy.R + merge_tree_accuracy.R first.")
}

# --- Table A: all models vs each other, within each scenario --------------

cli::cli_h1("Table A: all-models comparison (within scenario)")

ranking_rows  <- list()
friedman_rows <- list()

for (scen in c("mk", "nt")) {
  cli::cli_h2("Scenario: {scen}")

  scen_models <- sort(unique(cid_data$modelID[cid_data$scenario == scen]))
  scen_missing <- setdiff(PRESENT_MODELS, scen_models)
  if (length(scen_missing) > 0L) {
    cli::cli_alert_warning(
      "{scen}: no data for {paste(scen_missing, collapse = ', ')} in this scenario -- excluded from this table only."
    )
  }
  if (length(scen_models) < 2L) {
    cli::cli_alert_danger("{scen}: fewer than 2 models with data -- skipping Table A for this scenario.")
    next
  }

  res <- tryCatch(AllModelsComparison(cid_data, scen, models = scen_models), error = function(e) {
    cli::cli_alert_danger("Failed for {scen}: {conditionMessage(e)}")
    NULL
  })
  if (is.null(res)) next

  print(res$ranking, row.names = FALSE)
  cli::cli_alert_info(
    "Friedman chi-sq = {round(res$friedman$statistic, 2)}, df = {res$friedman$parameter}, p = {signif(res$friedman$p.value, 3)}"
  )
  if (res$n_dropped > 0L) {
    cli::cli_alert_warning("{res$n_dropped} incomplete blocks dropped (see warning above)")
  }

  res$ranking$scenario <- scen
  ranking_rows[[scen]]  <- res$ranking
  friedman_rows[[scen]] <- data.frame(
    scenario = scen,
    chi_sq   = unname(res$friedman$statistic),
    df       = unname(res$friedman$parameter),
    p_value  = res$friedman$p.value,
    n_complete = res$n_complete,
    n_dropped  = res$n_dropped
  )

  # Save the full pairwise p-value matrix per scenario -- too big for one
  # combined CSV, so one file each.
  pw_path <- file.path(out_dir, sprintf("model_comparison_pairwise_%s.csv", scen))
  utils::write.csv(res$pairwise$p.value, pw_path)
  cli::cli_alert_success("Pairwise p-value matrix saved: {pw_path}")
}

ranking_df  <- do.call(rbind, ranking_rows)
friedman_df <- do.call(rbind, friedman_rows)
utils::write.csv(ranking_df,  file.path(out_dir, "model_comparison_ranking.csv"),  row.names = FALSE)
utils::write.csv(friedman_df, file.path(out_dir, "model_comparison_friedman.csv"), row.names = FALSE)

# --- Table B: each model vs itself, nt-generated vs mk-generated ----------

cli::cli_h1("Table B: scenario contrast (nt-generated vs mk-generated, per model)")

contrast_rows <- list()
for (mid in PRESENT_MODELS) {
  res <- tryCatch(ScenarioContrast(cid_data, mid), error = function(e) {
    cli::cli_alert_warning("Skipped {mid}: {conditionMessage(e)}")
    NULL
  })
  if (is.null(res)) next
  contrast_rows[[mid]] <- res$summary
}
contrast_df <- do.call(rbind, contrast_rows)
print(contrast_df, row.names = FALSE)
utils::write.csv(contrast_df, file.path(out_dir, "model_comparison_scenario_contrast.csv"), row.names = FALSE)
cli::cli_alert_success("Saved: {file.path(out_dir, 'model_comparison_scenario_contrast.csv')}")

# --- Interpretation notes ---------------------------------------------------

cli::cli_h2("How to read this")
cli::cli_alert_info("Table A ranking: lower median_cid = more accurate. Check whether rank order differs between mk and nt.")
cli::cli_alert_info("Table B median_diff = CID(nt) - CID(mk) for the SAME model. Negative = model is more accurate when data actually matches its assumptions (expected for NT models). Near-zero/positive for model1 is the expected null result (baseline shouldn't care which scenario generated the data).")
