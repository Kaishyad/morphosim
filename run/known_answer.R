#Checks that 95% posterior credible intervals contain the true simulated value in ~95% of replicates

#Things:
#- Load the list of converged runs from check_convergence.R output.
#- For each replicate: load .log file, extract CI for tree_length and
#     gain-to-loss ratio with KnownAnswer.R::CredibleInterval(), compare to
#     known true values stored in simulation metadata .rds files.
#- Compute coverage rates per grid cell with KnownAnswer.R::CoverageRate().
#- Summarise and export with KnownAnswer.R::KnownAnswerSummary().

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

# Output paths
ka_rds <- file.path(OutputDir(), "results", "known_answer_summary.rds")
ka_csv <- file.path(OutputDir(), "results", "known_answer_summary.csv")

dir.create(dirname(ka_rds), showWarnings = FALSE, recursive = TRUE)

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

saveRDS(summary_df, ka_rds)
utils::write.csv(summary_df, ka_csv, row.names = FALSE)

cli::cli_alert_success("Known-answer summary saved to:")
cli::cli_alert_success("  RDS : {ka_rds}")
cli::cli_alert_success("  CSV : {ka_csv}")

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
