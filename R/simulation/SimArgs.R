#Converts rows of PARAM_GRID into positional argument vectors for passing to RevBayes scripts via rb --args on Hamilton.

#   row     <- PARAM_GRID[i, ]
#   simDir  <- SimDirAbs("nt", GridTag(row), SimID(rep))
#   rb_args <- NtSimArgs(row, simDir, seed = rep)

#' Build rb argument vector for NT generative simulation
#'
#' Argument order matches sim-by_nt_kv.Rev:
#'   [1] outDir     [2] n_taxa   [3] n_neo     [4] n_trans
#'   [5] gain_loss  [6] part_rate  [7] tree_length  [8] seed
#'
#' @param row     Single row of PARAM_GRID or REDUCED_GRID.
#' @param simDir  Absolute path to simulation output directory in the-matrix.
#' @param seed    Integer random seed (use replicate number).
#' @return Character vector of 8 positional arguments.
#' @export
NtSimArgs <- function(row, simDir, seed) {
  c(
    simDir,
    as.character(row$n_taxa),
    as.character(row$n_neo),
    as.character(row$n_trans),
    as.character(row$gain_loss),    # arg[5]: gain-to-loss ratio
    as.character(row$part_rate),    # arg[6]: transformational partition rate
    as.character(row$tree_length),
    as.character(seed)
  )
}

#' Build rb argument vector for Mk generative simulation
#'
#' Argument order matches sim-by_mk_kv.Rev.
#' args[5] (gain_loss) and args[6] (part_rate) are passed for interface
#' compatibility with NtSimArgs but are ignored by sim-by_mk_kv.Rev.
#'
#' @param row     Single row of PARAM_GRID or REDUCED_GRID.
#' @param simDir  Absolute path to simulation output directory in the-matrix.
#' @param seed    Integer random seed (use replicate number).
#' @return Character vector of 8 positional arguments.
#' @export
MkSimArgs <- function(row, simDir, seed) {
  c(
    simDir,
    as.character(row$n_taxa),
    as.character(row$n_neo),
    as.character(row$n_trans),
    as.character(row$gain_loss),    # passed but ignored under Mk
    as.character(row$part_rate),    # passed but ignored under Mk
    as.character(row$tree_length),
    as.character(seed)
  )
}

#' Build rb argument vector for inference (sim-mc3.Rev or imp-mc3.Rev)
#'
#' Argument order matches sim-mc3.Rev and imp-mc3.Rev:
#'   [1] simDir   [2] outDir   [3] scriptID  [4] minEss  [5] seed
#'
#' simDir:  where neo.nex / trans.nex live (simulations/)
#' outDir:  where logs, trees, checkpoints are written (results/)
#'
#' @param simDir    Absolute path to simulation directory in the-matrix.
#' @param outDir    Absolute path to inference output directory in the-matrix.
#' @param scriptID  Model script name without .Rev (e.g. "model1").
#' @param minEss    Minimum ESS stopping criterion. Default 333.
#' @param seed      Integer random seed. Default 0.
#' @return Character vector of 5 positional arguments.
#' @export
InferArgs <- function(simDir, outDir, scriptID, minEss = 333L, seed = 0L) {
  c(
    simDir,
    outDir,
    scriptID,
    as.character(minEss),
    as.character(seed)
  )
}

#' Select the correct simulation argument builder for a given scenario
#'
#' @param scenario "nt" or "mk"
#' @return NtSimArgs or MkSimArgs function
#' @export
SimArgsFn <- function(scenario) {
  switch(scenario,
    nt = NtSimArgs,
    mk = MkSimArgs,
    stop("Unknown scenario: ", scenario, ". Use 'nt' or 'mk'.")
  )
}
