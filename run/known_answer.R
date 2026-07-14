#Checks that 95% posterior credible intervals contain the true simulated value in ~95% of replicates

source("R/core/_setup.R")

# --- Argument parsing ---
args_cli      <- commandArgs(trailingOnly = TRUE)
scenario_flag <- args_cli[which(args_cli == "--scenario") + 1]
model_flag    <- args_cli[which(args_cli == "--model")    + 1]

SCENARIOS   <- if (!is.na(scenario_flag[1])) scenario_flag else c("nt", "mk")
EVAL_MODELS <- if (!is.na(model_flag[1]))    model_flag    else MODEL_IDS

message(sprintf("Scenarios: %s | Models: %s",
                paste(SCENARIOS,    collapse = ", "),
                paste(EVAL_MODELS,  collapse = ", ")))

# --- Per-model-job output paths
# When --model is given (one model per SLURM job, run concurrently), write to a
# per-scenario-per-model file rather than the shared known_answer_summary.rds.
SINGLE_MODEL_MODE <- !is.na(model_flag[1])

results_dir <- file.path(OutputDir(), "results")
dir.create(results_dir, showWarnings = FALSE, recursive = TRUE)

.KaFile <- function(scenario) {
  if (SINGLE_MODEL_MODE) {
    file.path(results_dir,
              sprintf("known_answer_summary_%s_%s.rds", scenario, EVAL_MODELS[1]))
  } else {
    file.path(results_dir, "known_answer_summary.rds")
  }
}

ka_rds <- file.path(results_dir, "known_answer_summary.rds")
ka_csv <- file.path(results_dir, "known_answer_summary.csv")

# --- Load convergence filter ---
conv_rds <- file.path(OutputDir(), "results", "convergence_summary.rds")

if (!file.exists(conv_rds)) {
  stop("Convergence summary not found at: ", conv_rds,
       "\nRun analysis/check_convergence.R first.")
}

conv_df   <- readRDS(conv_rds)
converged <- conv_df[conv_df$pass & conv_df$scenario %in% SCENARIOS, ]

cli::cli_alert_info(
  "{nrow(converged)} converged run(s) available for known-answer test."
)

# --- Run KnownAnswerSummary for each model ---
all_results <- list()

for (scenario in SCENARIOS) {
  cli::cli_h1(paste("Scenario:", scenario))
  conv_scenario <- converged[converged$scenario == scenario, ]
  grid          <- ScenarioGrid(scenario)  # FIX: use scenario-specific grid

  for (mi in seq_along(EVAL_MODELS)) {
    modelID    <- EVAL_MODELS[mi]
    conv_model <- conv_scenario[conv_scenario$modelID == modelID, ]
    n_conv     <- nrow(conv_model)

    cli::cli_alert_info("{n_conv} converged replicates for {modelID} ({scenario})")

    if (n_conv == 0L) {
      cli::cli_alert_warning("No converged replicates for {modelID} / {scenario}; skipping.")
      next
    }

    result <- tryCatch(
      KnownAnswerSummary(modelID  = modelID,
                         scenario = scenario,
                         grid     = grid,   # FIX: pass scenario grid
                         nRep     = N_REP),
      error = function(e) {
        cli::cli_alert_danger("KnownAnswerSummary failed for {modelID}/{scenario}: {conditionMessage(e)}")
        NULL
      }
    )

    if (!is.null(result)) {
      result$modelID  <- modelID
      result$scenario <- scenario
      all_results[[paste(scenario, modelID, sep = "_")]] <- result
    }
  }
}

# --- Combine and save ---
summary_df <- do.call(rbind,
                      all_results[!vapply(all_results, is.null, logical(1))])

if (is.null(summary_df) || nrow(summary_df) == 0L) {
  stop("No known-answer results produced. Check that converged log files exist.")
}

if (SINGLE_MODEL_MODE) {
  per_model_rds <- .KaFile(SCENARIOS[1])   # one scenario per job when --model set
  saveRDS(summary_df, per_model_rds)
  cli::cli_alert_success("Per-model known-answer saved to: {per_model_rds}")
  cli::cli_alert_info("Run merge_known_answer.R after all model jobs finish.")
} else {
  # Full run (no --model flag): load existing, merge, de-duplicate, save combined
  existing_df <- if (file.exists(ka_rds)) readRDS(ka_rds) else NULL
  combined_df <- if (!is.null(existing_df)) {
    key <- with(rbind(existing_df, summary_df),
                paste(scenario, gridTag, modelID, sep = "|"))
    rbind(existing_df, summary_df)[!duplicated(key, fromLast = TRUE), ]
  } else {
    summary_df
  }
  saveRDS(combined_df, ka_rds)
  utils::write.csv(combined_df, ka_csv, row.names = FALSE)
  cli::cli_alert_success("Known-answer summary saved to:")
  cli::cli_alert_success("  RDS : {ka_rds}")
  cli::cli_alert_success("  CSV : {ka_csv}")
}

# --- Console report ---
cli::cli_h2("Coverage rates (target ~0.95)")

for (mid in EVAL_MODELS) {
  sub <- summary_df[summary_df$modelID == mid, ]
  if (nrow(sub) == 0L) next

  cli::cli_h3(mid)
  cli::cli_alert_info(
    "tree_length  — mean coverage: {round(mean(sub$cov_tree_len,  na.rm=TRUE), 3)}"
  )
  cli::cli_alert_info(
    "rate_loss    — mean coverage: {round(mean(sub$cov_rate_loss, na.rm=TRUE), 3)}"
  )

  low_tl <- sub[!is.na(sub$cov_tree_len)  & sub$cov_tree_len  < 0.90, ]
  low_rl <- sub[!is.na(sub$cov_rate_loss) & sub$cov_rate_loss < 0.90, ]

  if (nrow(low_tl) > 0L) {
    cli::cli_alert_warning(
      "  {nrow(low_tl)} grid cell(s) with tree_length coverage < 0.90"
    )
  }
  if (nrow(low_rl) > 0L) {
    cli::cli_alert_warning(
      "  {nrow(low_rl)} grid cell(s) with rate_loss coverage < 0.90"
    )
  }
}
