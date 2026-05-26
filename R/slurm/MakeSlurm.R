# MakeSlurm.R
# Generates and submits SLURM inference jobs for the morphosim parameter grid.
# For each combination of (scenario, grid point, replicate, model), fills in
# the mc3sim.sh template and submits via sbatch on Hamilton.
# Adapted from QueueSim() in simFuncs.R (supervisor / neotrans).
#
# Depends on: FilePaths.R, zzz.R
# Usage:
#   source("R/_setup.R")
#   SubmitGrid(scenarios = c("nt", "mk"), models = paste0("model", 1:12))

#' Submit inference jobs for the full parameter grid
#'
#' @param scenarios Character vector of generative scenarios: "nt", "mk", or both.
#' @param models Character vector of model script names (e.g. "model1" ... "model12").
#' @param grid Data frame of parameter combinations. Defaults to .config$grid.
#' @param nRep Integer number of replicates per grid cell. Defaults to .config$nRep.
#' @param replace Logical: cancel and resubmit if job already in queue.
#' @param dryRun Logical: if TRUE, print sbatch commands without submitting.
#' @export
SubmitGrid <- function(scenarios  = c("nt", "mk"),
                       models     = paste0("model", 1:12),
                       grid       = .config$grid,
                       nRep       = .config$nRep,
                       replace    = FALSE,
                       dryRun     = FALSE) {

  template  <- readLines(SlurmTemplate())
  submitted <- 0
  skipped   <- 0

  for (scenario in scenarios) {
    for (gi in seq_len(nrow(grid))) {

      # Build grid tag from parameter values: used in dir names and job names
      gridTag <- GridTag(grid[gi, ])

      for (rep in seq_len(nRep)) {
        repID  <- sprintf("sim%03d", rep)
        simDir <- SimDir(scenario, gridTag, repID)

        # Skip if simulated data doesn't exist yet
        if (!file.exists(file.path(MatrixDir(), simDir, "neo.nex"))) {
          message("Skipping ", simDir, ": no simulated data found")
          skipped <- skipped + 1
          next
        }

        for (scriptID in models) {

          jobName <- paste(gridTag, repID, scriptID, sep = "_")

          # Check if output already exists
          outLog <- file.path(MatrixDir(), simDir,
                              paste0(scriptID, "_run_1.log"))
          treeGz <- file.path(MatrixDir(), simDir,
                              paste0(scriptID, "_run_1.tar.gz"))
          if (file.exists(outLog) || file.exists(treeGz)) {
            next  # Already completed
          }

          # Fill in SLURM template placeholders
          jobLines <- gsub("%SIMSCENARIO%", scenario,       template)
          jobLines <- gsub("%SIMREP%",      repID,          jobLines)
          jobLines <- gsub("%SCRIPTID%",    scriptID,       jobLines)
          jobLines <- gsub("%SEED%",        as.character(rep), jobLines)
          jobLines <- gsub("%GRID_TAG%",    gridTag,        jobLines)

          # Write filled template to slurm directory
          slurmFile <- file.path(SlurmDir(),
                                 paste0(jobName, ".sh"))
          writeLines(jobLines, slurmFile)

          # Submit
          cmd <- paste("sbatch", slurmFile)
          if (dryRun) {
            message("[DRY RUN] ", cmd)
          } else {
            result <- system(cmd)
            if (result == 0) {
              submitted <- submitted + 1
            } else {
              warning("sbatch failed for ", jobName)
            }
          }
        }
      }
    }
  }

  message("Submitted: ", submitted, "  Skipped: ", skipped)
  invisible(submitted)
}

#' Build a short tag string from a grid row
#'
#' @param gridRow Single row of the parameter grid data frame.
#' @return Character string e.g. "tl1.43_n0.50_c50"
#' @export
GridTag <- function(gridRow) {
  sprintf("tl%s_n%s_c%s",
          formatC(gridRow$tree_length, format = "f", digits = 2),
          formatC(gridRow$rate_loss,   format = "f", digits = 2),
          as.integer(gridRow$n_chars))
}

#' Path to simulation data directory within the-matrix
#'
#' @param scenario "nt" or "mk"
#' @param gridTag  Grid tag string from GridTag()
#' @param repID    Replicate ID string e.g. "sim001"
#' @return Relative path string
#' @export
SimDir <- function(scenario, gridTag, repID) {
  file.path("simulations", scenario, gridTag, repID)
}

#' Path to the SLURM template file
#' @export
SlurmTemplate <- function() {
  file.path(SlurmDir(), "mc3sim.sh")
}

#' Check which grid cells still need inference for a given model
#'
#' @param scenario "nt" or "mk"
#' @param scriptID Model script name
#' @param grid Parameter grid data frame
#' @param nRep Number of replicates
#' @return Data frame of incomplete combinations
#' @export
CheckIncomplete <- function(scenario, scriptID,
                            grid = .config$grid,
                            nRep = .config$nRep) {
  incomplete <- vector("list", nrow(grid) * nRep)
  k <- 1
  for (gi in seq_len(nrow(grid))) {
    gridTag <- GridTag(grid[gi, ])
    for (rep in seq_len(nRep)) {
      repID  <- sprintf("sim%03d", rep)
      simDir <- SimDir(scenario, gridTag, repID)
      logFile <- file.path(MatrixDir(), simDir,
                           paste0(scriptID, "_run_1.log"))
      treeGz  <- file.path(MatrixDir(), simDir,
                           paste0(scriptID, "_run_1.tar.gz"))
      if (!file.exists(logFile) && !file.exists(treeGz)) {
        incomplete[[k]] <- data.frame(scenario = scenario,
                                      gridTag  = gridTag,
                                      rep      = repID,
                                      model    = scriptID)
        k <- k + 1
      }
    }
  }
  do.call(rbind, incomplete[seq_len(k - 1)])
}
