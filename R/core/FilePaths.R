
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

# --- Simulation helpers ---

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
  file.path(OutputDir(), SimDir(scenario, gridTag, repID))
}

#' Relative path to an inference output directory within the-matrix
#' Inference outputs are kept separate from simulated data:
#'   results/<scenario>/<gridTag>/<repID>/<modelID>/
InferDir <- function(scenario, gridTag, repID, modelID) {
  file.path("results", scenario, gridTag, repID, modelID)
}

#' Absolute path to an inference output directory in the local the-matrix clone
InferDirAbs <- function(scenario, gridTag, repID, modelID) {
  file.path(OutputDir(), InferDir(scenario, gridTag, repID, modelID))
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

#' Path to a RevBayes MCMC full log file ({modelID}_run_{N}.log)
#'
#' Written every 36 iterations. Used for tree and general parameter inspection.
#' Stored in results/<scenario>/<gridTag>/<repID>/<modelID>/ (separate from sim data).
LogFile <- function(scenario, gridTag, repID, modelID, run = 1) {
  file.path(InferDirAbs(scenario, gridTag, repID, modelID),
            paste0(modelID, "_run_", run, ".log"))
}

#' Path to the stochastic-only parameter log (run_{N}.p.log)
ParamLogFile <- function(scenario, gridTag, repID, modelID, run = 1) {
  file.path(InferDirAbs(scenario, gridTag, repID, modelID),
            paste0(modelID, ".p_run_", run, ".log"))
}

#' Path to a compressed tree file
TreeGzFile <- function(scenario, gridTag, repID, modelID, run = 1) {
  file.path(InferDirAbs(scenario, gridTag, repID, modelID),
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

#' Alias for DiagFile — used by legacy Helpers.R::HasConverged()
ConvergenceFile <- function(scenario, gridTag, repID, modelID) {
  DiagFile(scenario, gridTag, repID, modelID)
}

#' Is an inference job actually complete?
#'
#' FIX (2026-07): this is the single, shared definition of "this job is
#' done" used by both slurm/Infer.R (deciding whether to skip re-submitting
#' a job) and run/check_convergence.R (deciding whether a job is ready to be
#' checked). Previously the two scripts used two different, independently
#' maintained checks that silently drifted apart:
#'   - Infer.R only checked run_1's .log file OR its .tar.gz, so a job that
#'     crashed after RevBayes wrote the first few lines of run_1's log (but
#'     never produced a run_2) was treated as "already done" and never
#'     resubmitted.
#'   - check_convergence.R required BOTH runs' .log files before it would
#'     even attempt CheckConvergence() on a replicate.
#'   A job crippled by the first, looser check therefore looked "finished"
#'   to Infer.R (so it was silently skipped forever) but was invisible to
#'   check_convergence.R (which never enumerated it, since run_2's log was
#'   missing) -- producing zero downstream rows with no error anywhere.
#'   This was the root cause of model12/mk showing "640 skipped" in Infer.R
#'   with zero .rds output anywhere downstream.
#'
#' A job counts as complete only when the full MCMC log exists for every
#' run (default 2). This deliberately does NOT look at .tar.gz/.trees
#' files: those are only used by tree-accuracy/convergence analysis, and a
#' log-complete-but-not-yet-tarred run is still a real, finished RevBayes
#' run, not a candidate for resubmission.
#'
#' @param scenario  "nt" or "mk"
#' @param gridTag   Grid tag string from GridTag()
#' @param repID     Replicate ID e.g. "sim001"
#' @param modelID   Model script name e.g. "model1"
#' @param nRuns     Number of independent MCMC runs expected (default 2)
#' @return Logical TRUE if the .log file exists for every run.
#' @export
JobLogsComplete <- function(scenario, gridTag, repID, modelID, nRuns = 2) {
  all(vapply(seq_len(nRuns), function(run) {
    file.exists(LogFile(scenario, gridTag, repID, modelID, run))
  }, logical(1)))
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

#' Build a grid tag string from a single grid row
#'
#' Includes part_rate when present (NT grid). Mk uses the unique()-collapsed
#' grid (no part_rate column) so falls back to the 3-field tag.
#' @param gridRow Single row of PARAM_GRID or Mk-collapsed grid
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

#' Return the grid appropriate for a given scenario
#'
#' NT uses the full PARAM_GRID (part_rate matters).
#' Mk uses the unique()-collapsed grid (part_rate irrelevant).
#' @param scenario "nt" or "mk"
ScenarioGrid <- function(scenario) {
  if (scenario == "mk") {
    unique(PARAM_GRID[, c("tree_length", "gain_loss", "n_char",
                           "n_taxa", "n_neo", "n_trans")])
  } else {
    PARAM_GRID
  }
}
