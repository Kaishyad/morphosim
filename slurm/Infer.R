# Submits inference jobs for the morphosim parameter grid on Hamilton.
# Mirrors Simulate.R exactly: uses sbatch --wrap (no .sh template files),
# which avoids all line-ending issues that plagued mc3sim.sh.
#
# Usage (run from /nobackup/djfb16/morphosim):
#   Rscript slurm/Infer.R                             # dry run, all models, both scenarios
#   Rscript slurm/Infer.R --run                       # submit all
#   Rscript slurm/Infer.R --run --scenario mk         # mk only
#   Rscript slurm/Infer.R --run --scenario mk --model model1   # mk + model1 only

source("R/core/_setup.R")

# --- Safety parameters (same pattern as Simulate.R) ---
MAX_QUEUE_DEPTH  <- 50L    # inference jobs are heavy (16 cores, ~24h) so keep low
POLL_INTERVAL_SEC <- 500L
SUBMIT_PAUSE_SEC  <- 0.5

# --- Argument parsing ---
args_cli      <- commandArgs(trailingOnly = TRUE)
dry_run       <- !("--run" %in% args_cli)
scenario_flag <- args_cli[which(args_cli == "--scenario") + 1]
model_flag    <- args_cli[which(args_cli == "--model")    + 1]

scenarios <- if (!is.na(scenario_flag[1])) scenario_flag else c("nt", "mk")
models    <- if (!is.na(model_flag[1]))    model_flag    else paste0("model", 1:12)

if (dry_run) message("Dry run — pass --run to submit jobs")
message(sprintf("Scenarios: %s | Models: %s",
                paste(scenarios, collapse = ", "),
                paste(models,    collapse = ", ")))

# --- Paths (resolved once, same layout as Simulate.R) ---
remote_dir <- getOption("ntRemoteDir")          # /nobackup/djfb16
rb_mpi     <- "/home/djfb16/diss/revbayes/projects/cmake/build-mpi/rb-mpi"
morphosim  <- file.path(remote_dir, "morphosim")
matrix_dir <- file.path(remote_dir, "the-matrix")
log_dir    <- file.path(morphosim, "logs")
infer_script <- file.path(morphosim, "rbScripts", "Inference", "sim-mc3.Rev")

# --- Queue helpers (identical to Simulate.R) ---
.queue_depth <- function() {
  out <- tryCatch(
    system("squeue -u \"$USER\" -h -o '%i' 2>/dev/null | wc -l",
           intern = TRUE, ignore.stderr = TRUE),
    error = function(e) "0"
  )
  as.integer(trimws(out[length(out)]))
}

.wait_for_slot <- function() {
  repeat {
    depth <- .queue_depth()
    if (depth < MAX_QUEUE_DEPTH) return(invisible(NULL))
    message(sprintf("  Queue depth %d >= limit %d — waiting %ds ...",
                    depth, MAX_QUEUE_DEPTH, POLL_INTERVAL_SEC))
    Sys.sleep(POLL_INTERVAL_SEC)
  }
}

# --- Inference loop ---
submitted <- 0L
skipped   <- 0L
failed    <- 0L

for (scenario in scenarios) {

  # Mk ignores part_rate — use collapsed grid (same as Simulate.R)
  grid <- if (scenario == "mk") {
    unique(PARAM_GRID[, c("tree_length", "gain_loss", "n_char",
                          "n_taxa", "n_neo", "n_trans")])
  } else {
    PARAM_GRID
  }

  for (gi in seq_len(nrow(grid))) {
    row     <- grid[gi, ]
    gridTag <- GridTag(row)

    for (rep in seq_len(N_REP)) {
      repID     <- SimID(rep)
      simDirAbs <- SimDirAbs(scenario, gridTag, repID)

      # Skip if simulated data doesn't exist
      if (!file.exists(file.path(simDirAbs, "neo.nex"))) {
        skipped <- skipped + 1L
        next
      }

      for (scriptID in models) {

        job_name <- paste0("inf_", scenario, "_", gridTag, "_", repID,
                           "_", scriptID)
        out_log  <- file.path(log_dir, paste0(job_name, ".out"))
        err_log  <- file.path(log_dir, paste0(job_name, ".err"))

        # Skip if inference output already exists
        inferDirAbs <- InferDirAbs(scenario, gridTag, repID, scriptID)
        log_file <- file.path(inferDirAbs, paste0(scriptID, "_run_1.log"))
        tar_file <- file.path(inferDirAbs, paste0(scriptID, "_run_1.tar.gz"))
        if (file.exists(log_file) || file.exists(tar_file)) {
          skipped <- skipped + 1L
          next
        }

        # Create inference output directory
        if (!dir.exists(inferDirAbs)) dir.create(inferDirAbs, recursive = TRUE)

        # Pass both simDirAbs (data) and inferDirAbs (outputs) to sim-mc3.Rev
        rb_args <- InferArgs(simDirAbs, inferDirAbs, scriptID, minEss = 333L, seed = rep)

        if (dry_run) {
          message(sprintf("[DRY RUN] %s | %s | %s | %s",
                          scenario, gridTag, repID, scriptID))
          message("  rb_args: ", paste(rb_args, collapse = " "))
          next
        }

        .wait_for_slot()

        # Build the --wrap command exactly like Simulate.R:
        # module loads + mpirun rb-mpi, no git push (handled by push_when_done.sh)
        infer_subdir <- file.path("results", scenario, gridTag, repID, scriptID)

        wrap_cmd <- paste(
          "module load gcc/11.2 boost/1.78.0 openmpi/4.1.1;",
          "cd", shQuote(morphosim), ";",
          "echo Starting", scriptID, "on", scenario, gridTag, repID, "at $(date);",
          "mpirun", shQuote(rb_mpi),
            shQuote(infer_script),
            paste(sapply(rb_args, shQuote), collapse = " "), ";",
          "cd", shQuote(file.path(matrix_dir, infer_subdir)), ";",
          "for f in ", paste0(scriptID, "_run_*.trees;"),
            "do [ -f \"$f\" ] &&",
            "tar -czf \"${f%.trees}.tar.gz\" \"$f\" &&",
            "rm \"$f\";",
          "done;",
          "echo Done at $(date)"
        )

        slurmCmd <- paste(
          "sbatch",
          "--ntasks=16",      # 16 MPI processes: 8 chains x 2 runs
          "--nodes=1",        # keep all on one node, avoids inter-node MPI overhead
          "--mem=4G",
          "--time=23:45:00",
          "--gres=tmp:16G",
          "-p shared",
          "--job-name", shQuote(job_name),
          "--output",   shQuote(out_log),
          "--error",    shQuote(err_log),
          "--wrap",     shQuote(wrap_cmd)
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
}

message(sprintf(
  "Submitted: %d  |  Skipped: %d  |  Failed: %d",
  submitted, skipped, failed
))
