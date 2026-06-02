#Checks MCMC convergence for every completed inference run across all simulations x 12 models, flags failures, and writes a re-queue list.

#Things to do:
# -all completed RevBayes .log and .trees file pairs.
# -Call Convergence.R::CheckConvergence() for each run (ESS >= 200, rank-normalised R-hat < 1.01, ASDSF < 0.01).
# -Save a convergence summary .rds (pass/fail per run with diagnostics).
# -Print a list of non-converged runs for re-submission with submit_inference.R.

source("R/core/_setup.R")

# --- Configuration ---
SCENARIOS <- c("nt", "mk")

#Output paths
conv_rds  <- file.path(OutputDir(), "results", "convergence_summary.rds")
requeue_f <- file.path(OutputDir(), "results", "requeue_list.txt")

dir.create(dirname(conv_rds), showWarnings = FALSE, recursive = TRUE)

#--- Helper ---
#run is complete when both log files exist for a given (scenario, gridTag, repID, modelID) 
.EnumerateCompleted <- function(scenario, grid = PARAM_GRID, nRep = N_REP,
                                 model_ids = MODEL_IDS, nRuns = 2) {
  rows <- vector("list", nrow(grid) * nRep * length(model_ids))
  k    <- 1L

  for (gi in seq_len(nrow(grid))) {
    gridTag <- GridTag(grid[gi, ])
    for (rep in seq_len(nRep)) {
      repID <- SimID(rep)
      for (mid in model_ids) {
        logs_exist <- all(vapply(seq_len(nRuns), function(run) {
          file.exists(LogFile(scenario, gridTag, repID, mid, run))
        }, logical(1)))

        if (logs_exist) {
          rows[[k]] <- data.frame(scenario  = scenario,
                                  gridTag   = gridTag,
                                  repID     = repID,
                                  modelID   = mid,
                                  stringsAsFactors = FALSE)
          k <- k + 1L
        }
      }
    }
  }

  do.call(rbind, rows[seq_len(k - 1L)])
}

# --- Main loop ---
all_conv <- vector("list", length(SCENARIOS))

for (si in seq_along(SCENARIOS)) {
  scenario <- SCENARIOS[si]
  cli::cli_h1(paste("Checking convergence:", scenario))

  completed <- .EnumerateCompleted(scenario)

  if (is.null(completed) || nrow(completed) == 0L) {
    cli::cli_alert_warning("No completed runs found for scenario: {scenario}")
    next
  }

  cli::cli_alert_info("{nrow(completed)} run(s) to check for scenario '{scenario}'")

  conv_rows <- vector("list", nrow(completed))

  for (ri in seq_len(nrow(completed))) {
    row     <- completed[ri, ]
    result  <- tryCatch(
      CheckConvergence(row$scenario, row$gridTag, row$repID, row$modelID),
      error = function(e) {
        warning("CheckConvergence failed for ",
                paste(row$scenario, row$gridTag, row$repID, row$modelID,
                      sep = "/"),
                ": ", conditionMessage(e))
        list(pass       = FALSE,
             rhat       = NULL,
             ess        = NULL,
             asdsf      = NA_real_,
             rhat_pass  = FALSE,
             ess_pass   = FALSE,
             asdsf_pass = FALSE)
      }
    )

    conv_rows[[ri]] <- data.frame(
      scenario   = row$scenario,
      gridTag    = row$gridTag,
      repID      = row$repID,
      modelID    = row$modelID,
      pass       = result$pass,
      rhat_max   = if (!is.null(result$rhat)) max(result$rhat,  na.rm = TRUE) else NA_real_,
      ess_min    = if (!is.null(result$ess))  min(result$ess,   na.rm = TRUE) else NA_real_,
      asdsf      = result$asdsf,
      rhat_pass  = result$rhat_pass,
      ess_pass   = result$ess_pass,
      asdsf_pass = result$asdsf_pass,
      stringsAsFactors = FALSE
    )

    if (ri %% 50L == 0L) {
      cli::cli_alert_info("  {ri}/{nrow(completed)} checked...")
    }
  }

  all_conv[[si]] <- do.call(rbind, conv_rows)
}

conv_df <- do.call(rbind, all_conv[!vapply(all_conv, is.null, logical(1))])

# --- Save summary ---
saveRDS(conv_df, conv_rds)
cli::cli_alert_success("Convergence summary saved to: {conv_rds}")

# --- Report ---
n_pass <- sum(conv_df$pass, na.rm = TRUE)
n_fail <- sum(!conv_df$pass, na.rm = TRUE)
n_tot  <- nrow(conv_df)

cli::cli_h2("Convergence summary")
cli::cli_alert_info("Total runs checked : {n_tot}")
cli::cli_alert_info("Passed             : {n_pass} ({round(100 * n_pass / n_tot, 1)}%)")
cli::cli_alert_info("Failed             : {n_fail} ({round(100 * n_fail / n_tot, 1)}%)")

#breakdown by failure criterion
fail_df <- conv_df[!conv_df$pass, ]
if (nrow(fail_df) > 0L) {
  cli::cli_h2("Failure breakdown")
  cli::cli_alert_info("R-hat failures  : {sum(!fail_df$rhat_pass,  na.rm = TRUE)}")
  cli::cli_alert_info("ESS failures    : {sum(!fail_df$ess_pass,   na.rm = TRUE)}")
  cli::cli_alert_info("ASDSF failures  : {sum(!fail_df$asdsf_pass, na.rm = TRUE)}")
}

# --- Write re-queue list --
failed_runs <- conv_df[!conv_df$pass, ]

if (nrow(failed_runs) == 0L) {
  cli::cli_alert_success("All runs passed — no re-queuing needed.")
  writeLines("# All runs converged; no re-submissions needed.", requeue_f)
} else {
  requeue_lines <- apply(failed_runs, 1, function(r) {
    paste(r["scenario"], r["gridTag"], r["repID"], r["modelID"], sep = "\t")
  })

  writeLines(
    c("# Failed runs for re-submission via submit_inference.R",
      "# Columns: scenario\tgridTag\trepID\tmodelID",
      requeue_lines),
    requeue_f
  )

  cli::cli_alert_warning(
    "{nrow(failed_runs)} failed run(s) written to: {requeue_f}"
  )
}
