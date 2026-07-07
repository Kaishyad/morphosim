#Posterior predictive simulation (PPS) adequacy testing.
#
#Wires up R/model/PPS.R (CharacterVariance / PPSForReplicate / PPSAdequacyRates)
#into a top-level driver, following the same CLI/per-model-file pattern as
#run/known_answer.R and run/gam_threshold.R. No driver previously existed for
#this stage even though the underlying functions were fully implemented.
#
#Usage:
#  Rscript run/pps_adequacy.R --scenario nt --model model8
#  Rscript run/pps_adequacy.R                       # all scenarios/models
#
#Requires: RevBayes ppsample.Rev output already generated per replicate
#(<simDir>/<modelID>/pps/pps_*.nex). Run on a representative subset of the
#grid per the dissertation's "Advanced Outcomes" plan, not necessarily the
#full grid.

source("R/core/_setup.R")

# --- Argument parsing ---
args_cli      <- commandArgs(trailingOnly = TRUE)
scenario_flag <- args_cli[which(args_cli == "--scenario") + 1]
model_flag    <- args_cli[which(args_cli == "--model")    + 1]
partition_flag <- args_cli[which(args_cli == "--partition") + 1]

SCENARIOS   <- if (!is.na(scenario_flag[1])) scenario_flag else c("nt", "mk")
EVAL_MODELS <- if (!is.na(model_flag[1]))    model_flag    else MODEL_IDS
PARTITIONS  <- if (!is.na(partition_flag[1])) partition_flag else c("neo", "trans")

message(sprintf("Scenarios: %s | Models: %s | Partitions: %s",
                paste(SCENARIOS,   collapse = ", "),
                paste(EVAL_MODELS, collapse = ", "),
                paste(PARTITIONS,  collapse = ", ")))

SINGLE_MODEL_MODE <- !is.na(model_flag[1])

results_dir <- file.path(OutputDir(), "results")
dir.create(results_dir, showWarnings = FALSE, recursive = TRUE)

pps_rds <- file.path(results_dir, "pps_adequacy.rds")
pps_csv <- file.path(results_dir, "pps_adequacy.csv")

.PpsFile <- function(scenario) {
  if (SINGLE_MODEL_MODE) {
    file.path(results_dir,
              sprintf("pps_adequacy_%s_%s.rds", scenario, EVAL_MODELS[1]))
  } else {
    pps_rds
  }
}

# --- Run PPSAdequacyRates for each scenario/model/partition ---
all_results <- list()

for (scenario in SCENARIOS) {
  cli::cli_h1(paste("Scenario:", scenario))
  grid <- ScenarioGrid(scenario)

  for (modelID in EVAL_MODELS) {
    for (partition in PARTITIONS) {
      cli::cli_alert_info("Running PPS for {modelID} / {scenario} / {partition}")

      result <- tryCatch(
        PPSAdequacyRates(modelID   = modelID,
                         scenario  = scenario,
                         partition = partition,
                         grid      = grid,
                         nRep      = N_REP),
        error = function(e) {
          cli::cli_alert_danger(
            "PPSAdequacyRates failed for {modelID}/{scenario}/{partition}: {conditionMessage(e)}"
          )
          NULL
        }
      )

      if (!is.null(result)) {
        all_results[[paste(scenario, modelID, partition, sep = "_")]] <- result
      }
    }
  }
}

# --- Combine and save ---
summary_df <- do.call(rbind,
                      all_results[!vapply(all_results, is.null, logical(1))])

if (is.null(summary_df) || nrow(summary_df) == 0L) {
  stop("No PPS adequacy results produced. Check that pps_*.nex files exist ",
       "under <simDir>/<modelID>/pps/.")
}

if (SINGLE_MODEL_MODE) {
  per_model_rds <- .PpsFile(SCENARIOS[1])
  saveRDS(summary_df, per_model_rds)
  cli::cli_alert_success("Per-model PPS results saved to: {per_model_rds}")
  cli::cli_alert_info("Merge per-model files the same way as known-answer results.")
} else {
  existing_df <- if (file.exists(pps_rds)) readRDS(pps_rds) else NULL
  combined_df <- if (!is.null(existing_df)) {
    key <- with(rbind(existing_df, summary_df),
                paste(scenario, gridTag, modelID, partition, sep = "|"))
    rbind(existing_df, summary_df)[!duplicated(key, fromLast = TRUE), ]
  } else {
    summary_df
  }
  saveRDS(combined_df, pps_rds)
  utils::write.csv(combined_df, pps_csv, row.names = FALSE)
  cli::cli_alert_success("PPS adequacy summary saved to:")
  cli::cli_alert_success("  RDS : {pps_rds}")
  cli::cli_alert_success("  CSV : {pps_csv}")
}

# --- Console report ---
cli::cli_h2("Adequacy rates (proportion of replicates with p > 0.05)")

for (mid in EVAL_MODELS) {
  sub <- summary_df[summary_df$modelID == mid, ]
  if (nrow(sub) == 0L) next

  cli::cli_h3(mid)
  for (part in PARTITIONS) {
    p_sub <- sub[sub$partition == part, ]
    if (nrow(p_sub) == 0L) next
    mean_adeq <- round(mean(p_sub$prop_adequate, na.rm = TRUE), 3)
    n_low <- sum(!is.na(p_sub$prop_adequate) & p_sub$prop_adequate < 0.80)
    cli::cli_alert_info(
      "{part}: mean adequacy = {mean_adeq} ({n_low} grid cell(s) below 0.80)"
    )
  }
}
