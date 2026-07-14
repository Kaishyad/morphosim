#Audits every (scenario x grid cell x replicate x model) combination and
#classifies it as complete / partial (crashed) / not started

source("R/core/_setup.R")

args_cli      <- commandArgs(trailingOnly = TRUE)
scenario_flag <- args_cli[which(args_cli == "--scenario") + 1]
model_flag    <- args_cli[which(args_cli == "--model")    + 1]

SCENARIOS <- if (!is.na(scenario_flag[1])) scenario_flag else c("nt", "mk")
MODELS    <- if (!is.na(model_flag[1]))    model_flag    else MODEL_IDS

results_dir <- file.path(OutputDir(), "results")
dir.create(results_dir, showWarnings = FALSE, recursive = TRUE)
audit_csv   <- file.path(results_dir, "incomplete_runs_audit.csv")
requeue_txt <- file.path(results_dir, "requeue_from_audit.txt")

cli::cli_h1("Auditing job completeness")
cli::cli_alert_info(sprintf("Scenarios: %s | Models: %s",
                            paste(SCENARIOS, collapse = ", "),
                            paste(MODELS,    collapse = ", ")))

# --- Per-run status for one job -------------------------------------------
# Returns a one-row data frame describing exactly which run(s) are missing,
# so "partial" rows in the audit are actionable at a glance rather than a
# bare TRUE/FALSE.
.JobStatus <- function(scenario, gridTag, repID, modelID, nRuns = 2) {
  simExists <- file.exists(file.path(
    SimDirAbs(scenario, gridTag, repID), "neo.nex"
  ))

  run_logs_exist <- vapply(seq_len(nRuns), function(run) {
    file.exists(LogFile(scenario, gridTag, repID, modelID, run))
  }, logical(1))

  complete <- all(run_logs_exist)

  status <- if (complete) {
    "complete"
  } else if (!simExists) {
    "not_started_no_sim_data"
  } else if (any(run_logs_exist)) {
    "partial_crashed"
  } else {
    "not_started"
  }

  data.frame(
    scenario        = scenario,
    gridTag         = gridTag,
    repID           = repID,
    modelID         = modelID,
    status          = status,
    sim_data_exists = simExists,
    run1_log        = run_logs_exist[1],
    run2_log        = if (nRuns >= 2) run_logs_exist[2] else NA,
    stringsAsFactors = FALSE
  )
}

# --- Main sweep -------------------------------------------------------------
all_rows <- vector("list", 0L)

for (scenario in SCENARIOS) {
  grid <- ScenarioGrid(scenario)
  cli::cli_h2("Scenario: {scenario} ({nrow(grid)} grid cells x {N_REP} reps x {length(MODELS)} models)")

  n_checked <- 0L
  for (gi in seq_len(nrow(grid))) {
    gridTag <- GridTag(grid[gi, ])
    for (rep in seq_len(N_REP)) {
      repID <- SimID(rep)
      for (mid in MODELS) {
        row <- .JobStatus(scenario, gridTag, repID, mid)
        if (row$status != "complete") {
          all_rows[[length(all_rows) + 1L]] <- row
        }
        n_checked <- n_checked + 1L
      }
    }
  }
  cli::cli_alert_info("  {n_checked} job(s) checked for {scenario}.")
}

audit_df <- do.call(rbind, all_rows)

if (is.null(audit_df) || nrow(audit_df) == 0L) {
  cli::cli_alert_success("Every checked job is complete (both runs' logs present). Nothing to report.")
  quit(save = "no", status = 0)
}

utils::write.csv(audit_df, audit_csv, row.names = FALSE)
cli::cli_alert_success("Full audit written to: {audit_csv} ({nrow(audit_df)} incomplete rows)")

# --- Console breakdown ------------------------------------------------------
cli::cli_h2("Breakdown by status")
print(table(audit_df$scenario, audit_df$status))

cli::cli_h2("Breakdown by scenario/model (incomplete counts)")
by_model <- aggregate(gridTag ~ scenario + modelID + status, data = audit_df, FUN = length)
names(by_model)[names(by_model) == "gridTag"] <- "n"
by_model <- by_model[order(by_model$scenario, by_model$modelID, by_model$status), ]
print(by_model, row.names = FALSE)

# --- Requeue list -----------------------------------------------------------
# Only rows where simulated data exists are actionable for resubmission --
# "not_started_no_sim_data" means the simulation step itself hasn't produced
# neo.nex yet, which is a different (upstream) problem for Simulate.R, not
# something slurm/Infer.R can fix by resubmitting inference.
requeueable <- audit_df[audit_df$status %in% c("partial_crashed", "not_started"), ]

if (nrow(requeueable) == 0L) {
  cli::cli_alert_info("No requeueable rows (all incompletes lack simulated data) -- nothing written to {requeue_txt}.")
} else {
  requeue_lines <- apply(requeueable, 1, function(r) {
    paste(r[["scenario"]], r[["gridTag"]], r[["repID"]], r[["modelID"]], sep = "\t")
  })
  writeLines(
    c("# Incomplete/crashed runs found by audit_incomplete_runs.R, ready for resubmission",
      "# Columns: scenario\tgridTag\trepID\tmodelID",
      requeue_lines),
    requeue_txt
  )
  cli::cli_alert_warning(
    "{nrow(requeueable)} job(s) written to {requeue_txt} for resubmission."
  )
}

n_no_sim <- sum(audit_df$status == "not_started_no_sim_data")
if (n_no_sim > 0L) {
  cli::cli_alert_warning(
    "{n_no_sim} row(s) have no simulated data at all (neo.nex missing) -- excluded from the requeue list. Check slurm/Simulate.R for these first."
  )
}

cli::cli_alert_info("Next step: review {requeue_txt}, then resubmit e.g. with a small wrapper around slurm/Infer.R's per-job sbatch logic, or by re-running slurm/Infer.R --run as normal -- it will now correctly NOT skip these, since JobLogsComplete() will return FALSE for all of them.")
