# R/FilePaths.R
# Path helpers for the morphosim simulation study.
# All functions read options set in R/_setup.R.

# --- Null-coalescing operator
`%||%` <- function(a, b) if (!is.null(a)) a else b

# --- Top-level directories

#' Root of the-matrix data repository (local clone)
OutputDir <- function() {
  getOption("ntOutDir") %||% stop("Set options('ntOutDir') in R/_setup.R")
}

#' simulations/ directory inside the-matrix
MatrixDir <- function() {
  getOption("ntRepoDir") %||% file.path(OutputDir(), "simulations")
}

#' SLURM scripts directory
SlurmDir <- function() {
  getOption("ntSlurmDir") %||% file.path(getwd(), "slurm")
}

#' RevBayes .Rev scripts directory
RBScriptDir <- function() {
  getOption("ntRBScriptDir") %||% file.path(getwd(), "rbScripts")
}

#' Remote nobackup path on Hamilton
RemoteDir <- function() {
  getOption("ntRemoteDir") %||% paste0("/nobackup/", Sys.getenv("USER"))
}

# --- Simulation helpers=

#' Format a replicate ID from an integer seed, e.g. "sim001"
SimID <- function(seed) sprintf("sim%03d", seed)

#' Relative path to a simulation directory within the-matrix
#' @param scenario "nt" or "mk"
#' @param gridTag  String from GridTag()
#' @param repID    e.g. "sim001"
SimDir <- function(scenario, gridTag, repID) {
  file.path("simulations", scenario, gridTag, repID)
}

#' Absolute path to a simulation directory in the local the-matrix clone
SimDirAbs <- function(scenario, gridTag, repID) {
  file.path(MatrixDir(), "..", SimDir(scenario, gridTag, repID))
}

#' Path to the true tree file for a replicate
SimTreeFile <- function(scenario, gridTag, repID) {
  file.path(SimDirAbs(scenario, gridTag, repID), "tree.nwk")
}

#' Path to a simulated nexus matrix
SimMatrixFile <- function(scenario, gridTag, repID, type = c("neo", "trans")) {
  type <- match.arg(type)
  file.path(SimDirAbs(scenario, gridTag, repID), paste0(type, ".nex"))
}

#' Path to a RevBayes MCMC log file
LogFile <- function(scenario, gridTag, repID, modelID, run = 1) {
  file.path(SimDirAbs(scenario, gridTag, repID),
            paste0(modelID, "_run_", run, ".log"))
}

#' Path to a compressed tree file
TreeGzFile <- function(scenario, gridTag, repID, modelID, run = 1) {
  file.path(SimDirAbs(scenario, gridTag, repID),
            paste0(modelID, "_run_", run, ".tar.gz"))
}

#' Path to a processed result .rds file (in the-matrix/results/)
ResultFile <- function(scenario, gridTag, repID, modelID) {
  d <- file.path(OutputDir(), "results", scenario, gridTag, repID)
  if (!dir.exists(d)) dir.create(d, recursive = TRUE)
  file.path(d, paste0(modelID, ".rds"))
}

#' Path to a convergence diagnostic text file (in the-matrix/diagnostics/)
DiagFile <- function(scenario, gridTag, repID, modelID) {
  d <- file.path(OutputDir(), "diagnostics", scenario, gridTag, repID)
  if (!dir.exists(d)) dir.create(d, recursive = TRUE)
  file.path(d, paste0(modelID, "-conv.txt"))
}

#' Path to a RevBayes .Rev script
RBScript <- function(modelID) {
  file.path(RBScriptDir(), paste0(modelID, ".Rev"))
}

#' Path to a filled SLURM job script
SlurmFile <- function(gridTag, repID, modelID) {
  file.path(SlurmDir(), paste0(gridTag, "_", repID, "_", modelID, ".sh"))
}

#' Path to the SLURM template
SlurmTemplate <- function() {
  file.path(SlurmDir(), "mc3sim.sh")
}

#' Build a grid tag string from a grid row
#' @param gridRow Single row of PARAM_GRID
GridTag <- function(gridRow) {
  sprintf("tl%s_gl%s_c%s",
          formatC(gridRow$tree_length, format = "f", digits = 2),
          formatC(gridRow$gain_loss,   format = "f", digits = 2),
          as.integer(gridRow$n_char))
}