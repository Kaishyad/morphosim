# null-coalescing operator
`%||%` <- function(a, b) if (!is.null(a)) a else b

# top-level directories

# root of the-matrix data repository (local clone)
OutputDir <- function() {
  getOption("ntOutDir") %||% stop("Set options('ntOutDir') in R/_setup.R")
}

# simulations/ directory inside the-matrix
MatrixDir <- function() {
  getOption("ntRepoDir") %||% file.path(OutputDir(), "simulations")
}

# slurm scripts directory
SlurmDir <- function() {
  getOption("ntSlurmDir") %||% file.path(getwd(), "slurm")
}

# revbayes .rev scripts directory
RBScriptDir <- function() {
  getOption("ntRBScriptDir") %||% file.path(getwd(), "rbScripts")
}

# remote nobackup path on hamilton
RemoteDir <- function() {
  getOption("ntRemoteDir") %||% paste0("/nobackup/", Sys.getenv("USER"))
}

# scratch tmp directory for large intermediate files, defaults to remotedir()/tmp
TmpDir <- function() {
  getOption("ntTmpDir") %||% file.path(RemoteDir(), "tmp")
}

# path to the compiled revbayes mpi binary
RbBinary <- function() {
  getOption("ntRbBinary") %||%
    file.path(Sys.getenv("HOME"), "diss/revbayes/projects/cmake/build-mpi/rb-mpi")
}

# simulation helpers

# format a replicate id from an integer seed, e.g. "sim001"
SimID <- function(seed) sprintf("sim%03d", seed)

# relative path to a simulation directory within the-matrix
SimDir <- function(scenario, gridTag, repID) {
  file.path("simulations", scenario, gridTag, repID)
}

# absolute path to a simulation directory in the local the-matrix clone
SimDirAbs <- function(scenario, gridTag, repID) {
  file.path(OutputDir(), SimDir(scenario, gridTag, repID))
}

# relative path to an inference output directory: results/<scenario>/<gridTag>/<repID>/<modelID>/
InferDir <- function(scenario, gridTag, repID, modelID) {
  file.path("results", scenario, gridTag, repID, modelID)
}

# absolute path to an inference output directory in the local the-matrix clone
InferDirAbs <- function(scenario, gridTag, repID, modelID) {
  file.path(OutputDir(), InferDir(scenario, gridTag, repID, modelID))
}

# path to the true tree file for a replicate
SimTreeFile <- function(scenario, gridTag, repID) {
  file.path(SimDirAbs(scenario, gridTag, repID), "tree.nwk")
}

# path to a simulated nexus matrix
SimMatrixFile <- function(scenario, gridTag, repID, type = c("neo", "trans")) {
  type <- match.arg(type)
  file.path(SimDirAbs(scenario, gridTag, repID), paste0(type, ".nex"))
}

# path to a revbayes mcmc full log file, written every 36 iterations
LogFile <- function(scenario, gridTag, repID, modelID, run = 1, prefix = "") {
  file.path(InferDirAbs(scenario, gridTag, repID, modelID),
            paste0(prefix, modelID, "_run_", run, ".log"))
}

# path to the stochastic-only parameter log (run_{n}.p.log)
ParamLogFile <- function(scenario, gridTag, repID, modelID, run = 1, prefix = "") {
  file.path(InferDirAbs(scenario, gridTag, repID, modelID),
            paste0(prefix, modelID, ".p_run_", run, ".log"))
}

# path to a compressed tree file
TreeGzFile <- function(scenario, gridTag, repID, modelID, run = 1, prefix = "") {
  file.path(InferDirAbs(scenario, gridTag, repID, modelID),
            paste0(prefix, modelID, "_run_", run, ".tar.gz"))
}

# path to a processed result .rds file (in the-matrix/results/)
ResultFile <- function(scenario, gridTag, repID, modelID) {
  d <- file.path(OutputDir(), "results", scenario, gridTag, repID)
  if (!dir.exists(d)) dir.create(d, recursive = TRUE)
  file.path(d, paste0(modelID, ".rds"))
}

# path to a convergence diagnostic text file (in the-matrix/diagnostics/)
DiagFile <- function(scenario, gridTag, repID, modelID) {
  d <- file.path(OutputDir(), "diagnostics", scenario, gridTag, repID)
  if (!dir.exists(d)) dir.create(d, recursive = TRUE)
  file.path(d, paste0(modelID, "-conv.txt"))
}

# alias for diagfile, used by helpers.r::hasconverged()
ConvergenceFile <- function(scenario, gridTag, repID, modelID) {
  DiagFile(scenario, gridTag, repID, modelID)
}

# is an inference job actually complete? true if the .log file exists for every run
JobLogsComplete <- function(scenario, gridTag, repID, modelID, nRuns = 2, prefix = "") {
  all(vapply(seq_len(nRuns), function(run) {
    file.exists(LogFile(scenario, gridTag, repID, modelID, run, prefix = prefix))
  }, logical(1)))
}

# path to a revbayes .rev script
RBScript <- function(modelID) {
  file.path(RBScriptDir(), paste0(modelID, ".Rev"))
}

# path to a filled slurm job script
SlurmFile <- function(gridTag, repID, modelID) {
  file.path(SlurmDir(), paste0(gridTag, "_", repID, "_", modelID, ".sh"))
}

# path to the slurm template
SlurmTemplate <- function() {
  file.path(SlurmDir(), "mc3sim.sh")
}

# build a grid tag string from a single grid row; includes part_rate when
# present (nt grid) - mk uses the unique()-collapsed grid so falls back to
# the 3-field tag
GridTag <- function(gridRow) {
  if (!is.null(gridRow$part_rate) && !is.na(gridRow$part_rate)) {
    sprintf("tl%s_gl%s_pr%s_c%s",
            formatC(gridRow$tree_length, format = "f", digits = 2),
            formatC(gridRow$gain_loss,   format = "f", digits = 2),
            formatC(gridRow$part_rate,   format = "f", digits = 2),
            as.integer(gridRow$n_char))
  } else {
    sprintf("tl%s_gl%s_c%s",
            formatC(gridRow$tree_length, format = "f", digits = 2),
            formatC(gridRow$gain_loss,   format = "f", digits = 2),
            as.integer(gridRow$n_char))
  }
}

# returns the grid for a given scenario
ScenarioGrid <- function(scenario) {
  if (scenario == "mk") {
    unique(PARAM_GRID[, c("tree_length", "gain_loss", "n_char",
                           "n_taxa", "n_neo", "n_trans")])
  } else {
    PARAM_GRID
  }
}
