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
#' @param grid Data frame of parameter combinations. Defaults to .config$grid
#'   for the "nt" scenario; for "mk" the unique()-collapsed ScenarioGrid("mk")
#'   is always used regardless of this argument, since part_rate is irrelevant
#'   to Mk (see Simulate.R for the matching collapse on the simulation side).
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
    
    # Mk ignores part_rate -- use the collapsed grid regardless of `grid` arg
    scenarioGrid <- if (scenario == "mk") ScenarioGrid("mk") else grid
    
    for (gi in seq_len(nrow(scenarioGrid))) {
      
      # Build grid tag from parameter values: used in dir names and job names
      gridTag <- GridTag(scenarioGrid[gi, ])
      
      for (rep in seq_len(nRep)) {
        repID   <- sprintf("sim%03d", rep)
        simDir  <- SimDir(scenario, gridTag, repID)      # relative, for job naming
        simDirAbs <- SimDirAbs(scenario, gridTag, repID) # absolute, for existence checks
        
        # Skip if simulated data doesn't exist yet
        if (!file.exists(file.path(simDirAbs, "neo.nex"))) {
          message("Skipping ", simDir, ": no simulated data found")
          skipped <- skipped + 1
          next
        }
        
        for (scriptID in models) {
          
          jobName <- paste(gridTag, repID, scriptID, sep = "_")
          
          # Check if output already exists
          outLog <- file.path(simDirAbs, paste0(scriptID, "_run_1.log"))
          treeGz <- file.path(simDirAbs, paste0(scriptID, "_run_1.tar.gz"))
          if (file.exists(outLog) || file.exists(treeGz)) {
            next  # Already completed
          }
          
          # Fill in SLURM template placeholders
          jobLines <- gsub("%SIMSCENARIO%", scenario,          template)
          jobLines <- gsub("%SIMREP%",      repID,             jobLines)
          jobLines <- gsub("%SCRIPTID%",    scriptID,          jobLines)
          jobLines <- gsub("%SEED%",        as.character(rep), jobLines)
          jobLines <- gsub("%GRID_TAG%",    gridTag,           jobLines)
          
          # Write filled template to slurm directory
          slurmFile <- file.path(SlurmDir(), paste0(jobName, ".sh"))
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

#' Check which grid cells still need inference for a given model
#'
#' @param scenario "nt" or "mk"
#' @param scriptID Model script name
#' @param grid Parameter grid data frame. For "mk", ScenarioGrid("mk") is
#'   always used instead (see SubmitGrid).
#' @param nRep Number of replicates
#' @return Data frame of incomplete combinations
#' @export
CheckIncomplete <- function(scenario, scriptID,
                            grid = .config$grid,
                            nRep = .config$nRep) {
  scenarioGrid <- if (scenario == "mk") ScenarioGrid("mk") else grid
  
  incomplete <- vector("list", nrow(scenarioGrid) * nRep)
  k <- 1
  for (gi in seq_len(nrow(scenarioGrid))) {
    gridTag <- GridTag(scenarioGrid[gi, ])
    for (rep in seq_len(nRep)) {
      repID     <- sprintf("sim%03d", rep)
      simDirAbs <- SimDirAbs(scenario, gridTag, repID)
      logFile   <- file.path(simDirAbs, paste0(scriptID, "_run_1.log"))
      treeGz    <- file.path(simDirAbs, paste0(scriptID, "_run_1.tar.gz"))
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
