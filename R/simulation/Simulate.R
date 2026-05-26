# analysis/simulate.R
# Generates simulated character matrices across the parameter grid.
# Loops over PARAM_GRID (defined in R/Grid.R), builds RevBayes argument
# vectors via R/SimArgs.R, creates output directories in the-matrix,
# and submits simulation jobs to Hamilton via sbatch.
#
# Usage:
#   Rscript analysis/simulate.R              # dry-run: prints args only
#   Rscript analysis/simulate.R --run        # submits all grid cells
#   Rscript analysis/simulate.R --run --reduced  # submits reduced grid only
#   Rscript analysis/simulate.R --run --scenario nt  # NT scenario only

source("R/_setup.R")

# ── Argument parsing ───────────────────────────────────────────────────────────

args_cli  <- commandArgs(trailingOnly = TRUE)
dry_run   <- !("--run"     %in% args_cli)
reduced   <- "--reduced"   %in% args_cli
scenario_flag <- args_cli[which(args_cli == "--scenario") + 1]
scenarios <- if (!is.na(scenario_flag)) scenario_flag else c("nt", "mk")

if (dry_run) message("Dry run — pass --run to submit jobs")

# ── Grid selection ─────────────────────────────────────────────────────────────

grid <- if (reduced) {
  message("Using REDUCED_GRID (", nrow(REDUCED_GRID), " combinations)")
  REDUCED_GRID
} else {
  message("Using full PARAM_GRID (", nrow(PARAM_GRID), " combinations)")
  PARAM_GRID
}

message(sprintf(
  "Grid: %d cells × %d replicates × %d scenarios = %d total simulation jobs",
  nrow(grid), N_REP, length(scenarios), nrow(grid) * N_REP * length(scenarios)
))

# ── Simulation loop ────────────────────────────────────────────────────────────

submitted <- 0L
skipped   <- 0L

for (scenario in scenarios) {
  
  # Select the correct argument builder from SimArgs.R
  argsFn <- SimArgsFn(scenario)
  
  # Select the correct Rev simulation script
  simScript <- if (scenario == "nt") "Sims/sim-by_nt_kv" else "Sims/sim-by_mk_kv"
  
  for (gi in seq_len(nrow(grid))) {
    row     <- grid[gi, ]
    gridTag <- GridTag(row)
    
    for (rep in seq_len(N_REP)) {
      repID      <- SimID(rep)
      simDirAbs  <- SimDirAbs(scenario, gridTag, repID)
      simDirRel  <- SimDir(scenario, gridTag, repID)
      
      # Skip if simulation outputs already exist
      if (file.exists(file.path(simDirAbs, "neo.nex")) &&
          file.exists(file.path(simDirAbs, "trans.nex")) &&
          file.exists(file.path(simDirAbs, "tree.nwk"))) {
        skipped <- skipped + 1L
        next
      }
      
      # Build positional argument vector for RevBayes
      rb_args <- argsFn(row, simDirAbs, seed = rep)
      
      if (dry_run) {
        message(sprintf("[DRY RUN] %s | %s | rep=%s",
                        scenario, gridTag, repID))
        message("  rb_args: ", paste(rb_args, collapse = " "))
      } else {
        # Create output directory in local the-matrix clone
        if (!dir.exists(simDirAbs)) {
          dir.create(simDirAbs, recursive = TRUE)
        }
        
        # Build and submit SLURM job
        # The SLURM template (mc3sim.sh) is filled by MakeSlurm.R for
        # inference jobs; for simulation we call rb directly via a
        # one-liner sbatch here since simulation is fast (< 5 min).
        slurmCmd <- paste(
          "sbatch",
          "--job-name", paste0("sim_", scenario, "_", gridTag, "_", repID),
          "--output", file.path(getOption("ntRemoteDir"), "morphosim", "logs",
                                paste0("sim_", scenario, "_", gridTag, "_",
                                       repID, ".out")),
          "--error",  file.path(getOption("ntRemoteDir"), "morphosim", "logs",
                                paste0("sim_", scenario, "_", gridTag, "_",
                                       repID, ".err")),
          "--wrap", paste(
            shQuote(file.path(getOption("ntRemoteDir"),
                              "diss/revbayes/projects/cmake/build-mpi/rb-mpi")),
            file.path(getOption("ntRemoteDir"), "morphosim/rbScripts", 
                      paste0(simScript, ".Rev")),
            paste(rb_args, collapse = " ")
          )
        )
        
        result <- system(slurmCmd)
        if (result == 0L) {
          submitted <- submitted + 1L
        } else {
          warning("sbatch failed for ", scenario, " ", gridTag, " ", repID)
        }
      }
    }
  }
}

message(sprintf("Submitted: %d  |  Skipped (already exist): %d",
                submitted, skipped))