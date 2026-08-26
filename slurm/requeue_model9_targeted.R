#!/usr/bin/env Rscript
# requeue_model9_targeted.R
#
# ONE-OFF, TARGETED requeue for exactly the 20 nt/model9 replicates that
# failed the ESS convergence check (rhat/asdsf pass, ess_min 24-194 vs
# minEss=333 target) at:
#   tl5.00_gl0.50_pr1.00_c200  sim001-sim010
#   tl5.00_gl1.00_pr1.00_c200  sim001-sim010
#
# Unlike Infer.R, this does NOT check JobLogsComplete() first -- these
# replicates already ran to completion (hit the 23h wall-time stopping
# rule) so JobLogsComplete() would see them as "done" and skip them.
# This script submits them anyway.
#
# Does NOT call requeue_failed.R -- the existing output dirs (including
# the .ckp checkpoint files) are left untouched on purpose. sim-mc3.Rev
# auto-resumes from the checkpoint (see sim-mc3.Rev lines ~72-76) rather
# than restarting from generation 0, as long as the .ckp file is still
# sitting in the same InferDirAbs() location.
#
# Usage:
#   Rscript slurm/requeue_model9_targeted.R           # dry run
#   Rscript slurm/requeue_model9_targeted.R --run     # actually submit
#
# Delete this file once these 20 replicates are confirmed passing.

source("R/core/_setup.R")

args_cli <- commandArgs(trailingOnly = TRUE)
dry_run  <- !("--run" %in% args_cli)

scenario   <- "nt"
scriptID   <- "model9"
grid_tags  <- c("tl5.00_gl0.50_pr1.00_c200", "tl5.00_gl1.00_pr1.00_c200")
rep_ids    <- sprintf("sim%03d", 1:10)

# Bump the wall-time ceiling for THIS submission only -- these chains are
# resuming close to the ESS target (24-194 vs 333), not starting cold, but
# the original 23h run only got the worst ones to ~24 ESS, so give real
# headroom rather than risking a second identical cutoff.
# CHECK your partition's actual MaxTime before using this (sinfo -p shared),
# and lower it if 47h exceeds what's allowed.
SLURM_TIME <- "47:45:00"

remote_dir   <- getOption("ntRemoteDir")
rb_mpi       <- RbBinary()
morphosim    <- file.path(remote_dir, "morphosim")
matrix_dir   <- file.path(remote_dir, "the-matrix")
log_dir      <- file.path(morphosim, "logs")
infer_script <- file.path(morphosim, "rbScripts", "Inference", "sim-mc3.Rev")

message(sprintf("Scenario: %s | Model: %s | Grid cells: %d | Reps each: %d | Total: %d",
                scenario, scriptID, length(grid_tags), length(rep_ids),
                length(grid_tags) * length(rep_ids)))
if (dry_run) message("Dry run -- pass --run to actually submit")

submitted <- 0L

for (gridTag in grid_tags) {
  for (repID in rep_ids) {

    simDirAbs   <- SimDirAbs(scenario, gridTag, repID)
    inferDirAbs <- InferDirAbs(scenario, gridTag, repID, scriptID)

    if (!dir.exists(inferDirAbs)) {
      message(sprintf("  SKIP (no existing output dir, nothing to resume): %s %s",
                      gridTag, repID))
      next
    }

    ckp_path <- file.path(inferDirAbs, paste0(scriptID, ".ckp"))
    has_ckp  <- file.exists(ckp_path)
    message(sprintf("  %s %s -- checkpoint %s",
                    gridTag, repID, if (has_ckp) "FOUND (will resume)" else "MISSING (will restart from gen 0)"))

    job_name <- paste0("inf_", scenario, "_", gridTag, "_", repID, "_", scriptID, "_requeue")
    out_log  <- file.path(log_dir, paste0(job_name, ".out"))
    err_log  <- file.path(log_dir, paste0(job_name, ".err"))

    rb_args <- InferArgs(simDirAbs, inferDirAbs, scriptID, minEss = 333L,
                         seed = as.integer(sub("sim", "", repID)))

    if (dry_run) {
      message(sprintf("    [DRY RUN] rb_args: %s", paste(rb_args, collapse = " ")))
      next
    }

    infer_subdir <- file.path("results", scenario, gridTag, repID, scriptID)

    wrap_cmd <- paste(
      "module load gcc/11.2 boost/1.78.0 openmpi/4.1.1;",
      "cd", shQuote(morphosim), ";",
      "echo Resuming", scriptID, "on", scenario, gridTag, repID, "at $(date);",
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
      "--ntasks=16",
      "--nodes=1",
      "--mem=8G",
      paste0("--time=", SLURM_TIME),
      "--gres=tmp:16G",
      "-p shared",
      "--job-name", shQuote(job_name),
      "--output",   shQuote(out_log),
      "--error",    shQuote(err_log),
      "--wrap",     shQuote(wrap_cmd)
    )

    message(sprintf("    Submitting: %s", job_name))
    system(slurmCmd)
    submitted <- submitted + 1L
    Sys.sleep(0.5)
  }
}

message(sprintf("Done. Submitted %d job(s).", submitted))
