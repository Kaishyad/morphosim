# generates and submits slurm jobs for all model x simulation combinations
#
# Rscript run/misc/submit_inference.R              # write slurm scripts only
# Rscript run/misc/submit_inference.R --submit     # also run sbatch
# Rscript run/misc/submit_inference.R --requeue    # re-submit only failed runs

source("R/core/_setup.R")

# fills the mc3sim.sh template and writes it to slurmPath
.WriteSlurmScript <- function(scenario, gridTag, repID, modelID, slurmPath) {
  template <- SlurmTemplate()
  if (!file.exists(template)) {
    stop("SLURM template not found: ", template)
  }

  lines <- readLines(template)

  seed_int <- as.integer(sub("sim0*", "", repID))   # "sim007" -> 7

  lines <- gsub("%SIMSCENARIO%", scenario,               lines)
  lines <- gsub("%GRID_TAG%",    gridTag,                lines)
  lines <- gsub("%SIMREP%",      repID,                  lines)
  lines <- gsub("%SCRIPTID%",    modelID,                lines)
  lines <- gsub("%SEED%",        as.character(seed_int), lines)

  dir.create(dirname(slurmPath), showWarnings = FALSE, recursive = TRUE)
  writeLines(lines, slurmPath)
  invisible(slurmPath)
}

args    <- commandArgs(trailingOnly = TRUE)
submit  <- "--submit"  %in% args
requeue <- "--requeue" %in% args
scenarios <- c("nt", "mk")

# requeue mode: reads the failed-run list from check_convergence.R
if (requeue) {
  requeue_f <- file.path(OutputDir(), "results", "requeue_list.txt")
  if (!file.exists(requeue_f)) {
    stop("Requeue list not found: ", requeue_f,
         "\nRun run/check_convergence.R first.")
  }

  lines  <- readLines(requeue_f)
  lines  <- lines[!grepl("^#", lines) & nchar(trimws(lines)) > 0]
  run_df <- do.call(rbind, lapply(lines, function(l) {
    parts <- strsplit(l, "\t")[[1]]
    if (length(parts) != 4L) return(NULL)
    data.frame(scenario = parts[1], gridTag = parts[2],
               repID    = parts[3], modelID  = parts[4],
               stringsAsFactors = FALSE)
  }))

  if (is.null(run_df) || nrow(run_df) == 0L) {
    message("No failed runs to requeue.")
    quit(save = "no", status = 0L)
  }

  cli::cli_alert_info("{nrow(run_df)} run(s) to requeue.")

  for (ri in seq_len(nrow(run_df))) {
    row        <- run_df[ri, ]
    slurm_path <- SlurmFile(row$gridTag, row$repID, row$modelID)

    .WriteSlurmScript(row$scenario, row$gridTag, row$repID, row$modelID,
                      slurm_path)

    if (submit) {
      system(paste("sbatch", shQuote(slurm_path)))
      message(sprintf("Requeued: %s x %s x %s",
                      row$scenario, row$repID, row$modelID))
    } else {
      message(sprintf("SLURM script written: %s", slurm_path))
    }
  }

  quit(save = "no", status = 0L)
}

# normal mode: iterates the full grid

seeds     <- seq_len(N_REP)
model_ids <- MODEL_IDS

n_written   <- 0L
n_submitted <- 0L
n_skipped   <- 0L

for (scenario in scenarios) {
  cli::cli_h1(paste("Scenario:", scenario))

  for (seed in seeds) {
    simID <- SimID(seed)

    for (modelID in model_ids) {

      for (gi in seq_len(nrow(PARAM_GRID))) {
        gridTag     <- GridTag(PARAM_GRID[gi, ])
        result_file <- ResultFile(scenario, gridTag, simID, modelID)

        # skip if result .rds already exists (run completed and processed)
        if (file.exists(result_file)) {
          n_skipped <- n_skipped + 1L
          next
        }

        slurm_path <- SlurmFile(gridTag, simID, modelID)
        .WriteSlurmScript(scenario, gridTag, simID, modelID, slurm_path)
        n_written <- n_written + 1L

        if (submit) {
          ret <- system(paste("sbatch", shQuote(slurm_path)))
          if (ret == 0L) {
            n_submitted <- n_submitted + 1L
            message(sprintf("Submitted : %s / %s / %s / %s",
                            scenario, gridTag, simID, modelID))
          } else {
            warning(sprintf("sbatch failed: %s / %s / %s / %s",
                            scenario, gridTag, simID, modelID))
          }
        } else {
          message(sprintf("Script written: %s", slurm_path))
        }
      }
    }
  }
}

cli::cli_h2("Done")
cli::cli_alert_info("Scripts written : {n_written}")
cli::cli_alert_info("Submitted       : {n_submitted}")
cli::cli_alert_info("Skipped (done)  : {n_skipped}")
