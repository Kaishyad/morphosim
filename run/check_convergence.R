#Checks MCMC convergence for every completed inference 


source("R/core/_setup.R")


args_cli       <- commandArgs(trailingOnly = TRUE)
scenario_flag  <- args_cli[which(args_cli == "--scenario")  + 1]
model_flag     <- args_cli[which(args_cli == "--model")     + 1]
max_trees_flag <- args_cli[which(args_cli == "--max-trees") + 1]

SCENARIOS  <- if (!is.na(scenario_flag[1])) scenario_flag else c("nt", "mk")
MODEL_IDS  <- if (!is.na(model_flag[1]))    model_flag    else paste0("model", 1:12)

# Allow overriding the O(n^2) tree-distance cap from the command line, e.g.
# --max-trees 300, without editing _setup.R. ComputeTreeESS() picks this up
# via TREE_ESS_MAX_TREES if set.
if (!is.na(max_trees_flag[1])) {
  TREE_ESS_MAX_TREES <- as.integer(max_trees_flag[1])
}

message(sprintf("Scenarios: %s | Models: %s%s",
                paste(SCENARIOS,  collapse = ", "),
                paste(MODEL_IDS,  collapse = ", "),
                if (exists("TREE_ESS_MAX_TREES")) sprintf(" | max-trees: %d", TREE_ESS_MAX_TREES) else ""))

# --- Per-model-job output paths
SINGLE_MODEL_MODE <- !is.na(model_flag[1])

results_dir <- file.path(OutputDir(), "results")
dir.create(results_dir, showWarnings = FALSE, recursive = TRUE)

.ConvFile <- function(scenario) {
  if (SINGLE_MODEL_MODE) {
    file.path(results_dir, sprintf("convergence_summary_%s_%s.rds", scenario, MODEL_IDS[1]))
  } else {
    file.path(results_dir, "convergence_summary.rds")
  }
}
requeue_f <- file.path(results_dir, "requeue_list.txt")

# --- Load existing results and skip already-checked rows (per scenario file)
existing_df <- NULL

.AlreadyChecked <- function(scenario, gridTag, repID, modelID) {
  if (is.null(existing_df)) return(FALSE)
  any(existing_df$scenario == scenario &
      existing_df$gridTag  == gridTag  &
      existing_df$repID    == repID    &
      existing_df$modelID  == modelID)
}

#--- Helper
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
        
        if (logs_exist && !.AlreadyChecked(scenario, gridTag, repID, mid)) {
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
  
  if (k == 1L) return(NULL)
  do.call(rbind, rows[seq_len(k - 1L)])
}

# --- Main loop
all_conv <- vector("list", length(SCENARIOS))

for (si in seq_along(SCENARIOS)) {
  scenario <- SCENARIOS[si]
  cli::cli_h1(paste("Checking convergence:", scenario))

  conv_rds    <- .ConvFile(scenario)
  existing_df <- if (file.exists(conv_rds)) readRDS(conv_rds) else NULL

  completed <- .EnumerateCompleted(scenario, grid = ScenarioGrid(scenario))
  
  if (is.null(completed) || nrow(completed) == 0L) {
    cli::cli_alert_info("No new runs to check for scenario: {scenario}")
    next
  }
  
  cli::cli_alert_info("{nrow(completed)} run(s) to check for scenario '{scenario}'")
  
  conv_rows <- vector("list", nrow(completed))
  rep_times <- numeric(nrow(completed))
  
  for (ri in seq_len(nrow(completed))) {
    row     <- completed[ri, ]
    t0      <- Sys.time()
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
             tree_ess   = NA_real_,
             asdsf      = NA_real_,
             rhat_pass  = FALSE,
             ess_pass   = FALSE,
             asdsf_pass = FALSE)
      }
    )
    rep_times[ri] <- as.numeric(Sys.time() - t0, units = "secs")
    
    conv_rows[[ri]] <- data.frame(
      scenario   = row$scenario,
      gridTag    = row$gridTag,
      repID      = row$repID,
      modelID    = row$modelID,
      pass       = result$pass,
      rhat_max   = if (!is.null(result$rhat))          max(result$rhat, na.rm = TRUE) else NA_real_,
      ess_min    = if (!is.null(result$ess))            min(result$ess,  na.rm = TRUE) else NA_real_,
      tree_ess   = if (!is.null(result$tree_ess))       result$tree_ess                else NA_real_,
      asdsf      = result$asdsf,
      rhat_pass  = result$rhat_pass,
      ess_pass   = result$ess_pass,
      asdsf_pass = result$asdsf_pass,
      stringsAsFactors = FALSE
    )
    
    if (ri %% 50L == 0L) {
      cli::cli_alert_info("  {ri}/{nrow(completed)} checked... (avg {round(mean(rep_times[seq_len(ri)]), 2)}s/run, last 50 avg {round(mean(rep_times[max(1, ri-49):ri]), 2)}s/run)")

      # Checkpoint progress so far so a SLURM walltime kill or node failure
      # doesn't lose everything checked in this session. Safe to do
      # repeatedly: combines with existing_df exactly as the final save does.
      partial_new <- do.call(rbind, conv_rows[seq_len(ri)])
      partial_df  <- if (!is.null(existing_df)) rbind(existing_df, partial_new) else partial_new
      saveRDS(partial_df, conv_rds)
    }
  }
  
  all_conv[[si]] <- do.call(rbind, conv_rows)

  # Save this scenario's file (per-model file if SINGLE_MODEL_MODE, else the
  # shared combined file) with its own results merged in.
  existing_df <- if (!is.null(existing_df)) rbind(existing_df, all_conv[[si]]) else all_conv[[si]]
  saveRDS(existing_df, conv_rds)
  cli::cli_alert_success("Saved: {conv_rds} ({nrow(existing_df)} total rows)")
}

# --- Final summary
conv_df <- do.call(rbind, lapply(SCENARIOS, function(s) {
  f <- .ConvFile(s)
  if (file.exists(f)) readRDS(f) else NULL
}))

if (is.null(conv_df) || nrow(conv_df) == 0L) {
  cli::cli_alert_info("No results to report.")
  quit(save = "no", status = 0)
}

# --- Report on full combined dataset
n_pass <- sum(conv_df$pass, na.rm = TRUE)
n_fail <- sum(!conv_df$pass, na.rm = TRUE)
n_tot  <- nrow(conv_df)

cli::cli_h2("Convergence summary (all runs to date)")
cli::cli_alert_info("Total runs checked : {n_tot}")
cli::cli_alert_info("Passed             : {n_pass} ({round(100 * n_pass / n_tot, 1)}%)")
cli::cli_alert_info("Failed             : {n_fail} ({round(100 * n_fail / n_tot, 1)}%)")

# Breakdown by model
cli::cli_h2("Pass rate by scenario/model")
by_model <- aggregate(pass ~ scenario + modelID, data = conv_df, FUN = mean)
by_model$pass <- round(by_model$pass * 100, 1)
print(by_model)

# Breakdown by failure criterion
fail_df <- conv_df[!conv_df$pass, ]
if (nrow(fail_df) > 0L) {
  cli::cli_h2("Failure breakdown")
  cli::cli_alert_info("R-hat failures  : {sum(!fail_df$rhat_pass,  na.rm = TRUE)}")
  cli::cli_alert_info("ESS failures    : {sum(!fail_df$ess_pass,   na.rm = TRUE)}")
  cli::cli_alert_info("ASDSF failures  : {sum(!fail_df$asdsf_pass, na.rm = TRUE)}")
}

# Tree ESS vs scalar ESS comparison (Martin's diagnostic)
has_tree_ess <- !is.na(conv_df$tree_ess) & !is.na(conv_df$ess_min)
if (any(has_tree_ess)) {
  ratio <- conv_df$tree_ess[has_tree_ess] / conv_df$ess_min[has_tree_ess]
  cli::cli_h2("Tree ESS vs scalar ESS (move schedule check)")
  cli::cli_alert_info("Median tree_ess / ess_min ratio : {round(median(ratio), 2)}")
  cli::cli_alert_info("Runs with tree_ess << ess_min (ratio < 0.5): {sum(ratio < 0.5)}")
  cli::cli_alert_info("Runs with tree_ess >> ess_min (ratio > 2.0): {sum(ratio > 2.0)}")
}

# --- Write re-queue list (all failures across combined dataset)
if (SINGLE_MODEL_MODE) {
  cli::cli_alert_info("Per-model mode: skipping shared requeue_list.txt (run merge_convergence.R after all model jobs finish).")
  quit(save = "no", status = 0)
}

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
