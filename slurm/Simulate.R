#Generates simulated character matrices across the parameter grid.
#Loops over PARAM_GRID, builds RevBayes argument vectors, creates output
#directories in the-matrix, and submits simulation jobs to Hamilton

#Rscript slurm/Simulate.R    # dry-run: prints args only
#Rscript slurm/Simulate.R --run   # submits all grid cells (both scenarios)
#Rscript slurm/Simulate.R --run --scenario nt   # NT only
#Rscript slurm/Simulate.R --run --scenario mk   # Mk only

source("R/core/_setup.R")


# Hamilton8 safety parameters
# throttle via MAX_QUEUE_DEPTH.
MAX_QUEUE_DEPTH <- 200L

# Pause (seconds) between queue-depth checks when the queue is full.
POLL_INTERVAL_SEC <- 30L

# Pause (seconds) between individual sbatch calls within a batch.
# A small gap avoids hammering the SLURM daemon.
SUBMIT_PAUSE_SEC <- 0.25


# Argument parsing
args_cli      <- commandArgs(trailingOnly = TRUE)
dry_run       <- !("--run"      %in% args_cli)
scenario_flag <- args_cli[which(args_cli == "--scenario") + 1]
scenarios     <- if (!is.na(scenario_flag[1])) scenario_flag else c("nt", "mk")

if (dry_run) message("Dry run — pass --run to submit jobs")

grid <- PARAM_GRID
message("Using full PARAM_GRID (", nrow(PARAM_GRID), " combinations)")
message(sprintf(
  "Grid: %d cells x %d replicates x %d scenario(s) = %d total simulation jobs",
  nrow(grid), N_REP, length(scenarios), nrow(grid) * N_REP * length(scenarios)
))


# Helper: current number of jobs in queue belonging to this user
.queue_depth <- function() {
  out <- tryCatch(
    system("squeue -u \"$USER\" -h -o '%i' 2>/dev/null | wc -l",
           intern = TRUE, ignore.stderr = TRUE),
    error = function(e) "0"
  )
  as.integer(trimws(out[length(out)]))
}


# Helper: wait until there is room in the queue
.wait_for_slot <- function(max_depth = MAX_QUEUE_DEPTH,
                           poll_sec  = POLL_INTERVAL_SEC) {
  repeat {
    depth <- .queue_depth()
    if (depth < max_depth) return(invisible(NULL))
    message(sprintf(
      "  Queue depth %d >= limit %d — waiting %ds ...",
      depth, max_depth, poll_sec
    ))
    Sys.sleep(poll_sec)
  }
}


# Simulation loop


# Paths resolved once (Hamilton remote layout)
remote_dir  <- getOption("ntRemoteDir")            # /nobackup/<user>
rb_bin      <- "rb"
log_dir     <- file.path(remote_dir, "morphosim", "logs")
rb_scripts  <- file.path(remote_dir, "morphosim", "rbScripts")

submitted <- 0L
skipped   <- 0L
failed    <- 0L

for (scenario in scenarios) {

  # Mk doesn't use part_rate — collapse to unique combinations
  grid <- if (scenario == "mk") {
    unique(PARAM_GRID[, c("tree_length", "gain_loss", "n_char", "n_taxa", "n_neo", "n_trans")])
  } else {
    PARAM_GRID
  }
  
  argsFn    <- SimArgsFn(scenario)
  simScript <- if (scenario == "nt") "Sims/sim-by_nt_kv" else "Sims/sim-by_mk_kv"

  for (gi in seq_len(nrow(grid))) {
    row     <- grid[gi, ]
    gridTag <- GridTag(row)

    for (rep in seq_len(N_REP)) {
      repID     <- SimID(rep)
      simDirAbs <- SimDirAbs(scenario, gridTag, repID)

      # Skip if all three output files already exist
      if (file.exists(file.path(simDirAbs, "neo.nex"))  &&
          file.exists(file.path(simDirAbs, "trans.nex")) &&
          file.exists(file.path(simDirAbs, "tree.nwk"))) {
        skipped <- skipped + 1L
        next
      }

      # Build positional argument vector for RevBayes
      rb_args <- argsFn(row, simDirAbs, seed = rep)

      job_name <- paste0("sim_", scenario, "_", gridTag, "_", repID)
      out_log  <- file.path(log_dir, paste0(job_name, ".out"))
      err_log  <- file.path(log_dir, paste0(job_name, ".err"))

      if (dry_run) {
        message(sprintf("[DRY RUN] %s | %s | rep=%s", scenario, gridTag, repID))
        message("  rb_args: ", paste(rb_args, collapse = " "))
        next
      }

      # Create output directory
      if (!dir.exists(simDirAbs)) dir.create(simDirAbs, recursive = TRUE)

      # Wait until there is a free slot in the queue
      .wait_for_slot()


      slurmCmd <- paste(
        "sbatch",
        "--job-name", shQuote(job_name),
        "--output",   shQuote(out_log),
        "--error",    shQuote(err_log),
        "--time=00:30:00",
        "--wrap", shQuote(paste(
          "module load gcc/11.2 boost/1.77.0 bioinformatics revbayes;",
          shQuote(rb_bin),
          shQuote(file.path(rb_scripts, paste0(simScript, ".Rev"))),
          "--args",
          paste(rb_args, collapse = " ")
        ))
      )

      result <- system(slurmCmd, ignore.stdout = TRUE)

      if (result == 0L) {
        submitted <- submitted + 1L
      } else {
        warning("sbatch failed for ", job_name)
        failed <- failed + 1L
      }

      Sys.sleep(SUBMIT_PAUSE_SEC)
    }
  }
}

message(sprintf(
  "Submitted: %d  |  Skipped (already exist): %d  |  Failed: %d",
  submitted, skipped, failed
))
