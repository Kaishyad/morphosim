# R/FilePaths.R
# Path-helper functions for the nt-sim simulation study.
# All functions read options set in R/_setup.R.

#' Root directory for analytical outputs (= root of nt-sim-data clone)
OutputDir <- function() {
  getOption("ntOutDir") %||% stop("Set options('ntOutDir') in R/_setup.R")
}

#' Directory for RevBayes inference repos (simulations/ in nt-sim-data)
RepoDir <- function() {
  getOption("ntRepoDir") %||% file.path(OutputDir(), "simulations")
}

#' Directory for SLURM scripts
SlurmDir <- function() {
  getOption("ntSlurmDir") %||% file.path(getwd(), "slurm")
}

#' Directory for RevBayes .Rev scripts
RBScriptDir <- function() {
  getOption("ntRBScriptDir") %||% file.path(getwd(), "rbScripts")
}

#' Remote nobackup path on Hamilton
RemoteDir <- function() {
  getOption("ntRemoteDir") %||% paste0("/nobackup/", Sys.getenv("USER"))
}

# ── Simulation-specific helpers ───────────────────────────────────────────────

#' Format a simulation ID from an integer seed
#' @param seed Integer seed.
#' @return Character string e.g. "sim001".
SimID <- function(seed) sprintf("sim%03d", seed)

#' Directory for a single simulation replicate
#' @param simID e.g. "sim001"
SimDir <- function(simID) {
  file.path(RepoDir(), simID)
}

#' Path to the true tree for a simulation replicate
SimTreeFile <- function(simID) {
  file.path(SimDir(simID), "tree.nwk")
}

#' Path to a simulated nexus matrix
#' @param type One of "neo" or "trans"
SimMatrixFile <- function(simID, type = c("neo", "trans")) {
  type <- match.arg(type)
  file.path(SimDir(simID), paste0(type, ".nex"))
}

#' Directory for RevBayes MCMC outputs (logs/ in nt-sim-data)
LogDir <- function(simID, modelID) {
  d <- file.path(OutputDir(), "logs", simID, modelID)
  if (!dir.exists(d)) dir.create(d, recursive = TRUE)
  d
}

#' Directory for processed results
ResultsDir <- function(simID) {
  d <- file.path(OutputDir(), "results", simID)
  if (!dir.exists(d)) dir.create(d, recursive = TRUE)
  d
}

#' Path to a processed result .rds file
ResultFile <- function(simID, modelID) {
  file.path(ResultsDir(simID), paste0(simID, "_", modelID, ".rds"))
}

#' Directory for convergence diagnostic text files
DiagDir <- function(simID) {
  d <- file.path(OutputDir(), "diagnostics", simID)
  if (!dir.exists(d)) dir.create(d, recursive = TRUE)
  d
}

#' Path to a convergence diagnostic text file
DiagFile <- function(simID, modelID) {
  file.path(DiagDir(simID), paste0(simID, "_", modelID, "-conv.txt"))
}

#' Path to a RevBayes .Rev script
RBScript <- function(modelID) {
  file.path(RBScriptDir(), paste0(modelID, ".Rev"))
}

#' Path to a SLURM job script
SlurmFile <- function(simID, modelID) {
  file.path(SlurmDir(), paste0(simID, "_", modelID, ".sh"))
}

# ── Null-coalescing operator ───────────────────────────────────────────────────
`%||%` <- function(a, b) if (!is.null(a)) a else b
