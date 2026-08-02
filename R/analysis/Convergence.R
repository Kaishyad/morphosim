# MCMC convergence diagnostics for inference runs

#Rank-normalised R-hat < RHAT_MAX
# ESS > ESS_MIN for all continuous parameters
#ASDSF < ASDSF_MAX across paired tree files


#' Rank-normalised split R-hat (Vehtari et al. 2021)
#'
#' Reads the .p.log file for each run, splits each chain's samples in half,
#' rank-normalises all splits, then computes the standard Gelman-Rubin
#' variance ratio. Sensitive to convergence failures in heavy-tailed
#' posteriors that standard PSRF can miss.
#'
#'
#' @param scenario  "nt" or "mk"
#' @param gridTag   Grid tag string from GridTag()
#' @param repID     Replicate ID e.g. "sim001"
#' @param modelID   Model script name e.g. "model1"
#' @param nRuns     Number of independent runs (default 2)
#' @return Named numeric vector of R-hat values, one per parameter.
#' @export
ComputeRhat <- function(scenario, gridTag, repID, modelID, nRuns = 2) {
  logs <- lapply(seq_len(nRuns), function(run) {
    f <- ParamLogFile(scenario, gridTag, repID, modelID, run)
    if (!file.exists(f)) return(NULL)
    read.table(f, header = TRUE, comment.char = "#")
  })

  if (any(vapply(logs, is.null, logical(1)))) {
    warning("Missing .p.log file for ", modelID, " ", gridTag, " ", repID)
    return(NULL)
  }

  #Drop iteration column; keep only numeric parameters
  params <- intersect(colnames(logs[[1]]), colnames(logs[[2]]))
  params <- params[params != "Iteration"]

  #Rank-normalise: convert each chain's samples to normal scores
  .RankNorm <- function(x) {
    r <- rank(x, ties.method = "average")
    qnorm((r - 0.375) / (length(r) + 0.25))
  }

  #Split each run in half to create 2*nRuns chains
  chains <- unlist(lapply(logs, function(log) {
    n   <- nrow(log)
    mid <- floor(n / 2)
    list(log[seq_len(mid), params],
         log[seq(mid + 1, n), params])
  }), recursive = FALSE)

  vapply(params, function(p) {
    x <- lapply(chains, function(ch) .RankNorm(ch[[p]]))
    m <- length(x)
    n <- length(x[[1]])
    B <- n * var(vapply(x, mean, numeric(1)))
    W <- mean(vapply(x, var, numeric(1)))
    sqrt(((n - 1) / n * W + B / n) / W)
  }, numeric(1))
}



#' Effective Sample Size per parameter
#'
#' Uses the autocorrelation-based ESS estimate. Flags parameters below
#' ESS_MIN (defined in _setup.R).
#'
#'
#' @inheritParams ComputeRhat
#' @return Named numeric vector of ESS values.
#' @export
ComputeESS <- function(scenario, gridTag, repID, modelID, nRuns = 2) {
  logs <- lapply(seq_len(nRuns), function(run) {
    f <- ParamLogFile(scenario, gridTag, repID, modelID, run)
    if (!file.exists(f)) return(NULL)
    read.table(f, header = TRUE, comment.char = "#")
  })

  if (any(vapply(logs, is.null, logical(1)))) {
    warning("Missing .p.log file for ", modelID, " ", gridTag, " ", repID)
    return(NULL)
  }

  params <- setdiff(colnames(logs[[1]]), "Iteration")

  .ESS1 <- function(x) {
    n  <- length(x)
    ac <- acf(x, lag.max = n - 1, plot = FALSE)$acf[-1]
    #Geyer's initial positive sequence estimator
    pairs   <- ac[seq(1, length(ac) - 1, 2)] + ac[seq(2, length(ac), 2)]
    cutoff  <- which(pairs < 0)[1]
    if (is.na(cutoff)) cutoff <- length(pairs)
    rho_sum <- 1 + 2 * sum(ac[seq_len(2 * cutoff - 1)])
    max(1, n / rho_sum)
  }

  #Pool ESS across runs (sum of independent ESS values)
  vapply(params, function(p) {
    ess_per_run <- vapply(logs, function(log) .ESS1(log[[p]]), numeric(1))
    sum(ess_per_run)
  }, numeric(1))
}



#' Load and parse posterior tree samples for one run, with cleanup
#'
#' Centralises tree-file extraction so it happens exactly once per
#' (scenario, gridTag, repID, modelID, run) regardless of how many
#' downstream diagnostics need the trees. If the source is a .tar.gz,
#' it is extracted to a tempfile under TmpDir() (see R/core/FilePaths.R) which is
#' always removed on exit (success, error, or timeout) via on.exit() —
#' previously these tempfiles were never cleaned up, and were found to
#' have accumulated to 45GB / ~24k files, degrading filesystem
#' performance for the whole convergence run.
#'
#' @inheritParams ComputeRhat
#' @param run Integer run index (1 or 2).
#' @return A `multiPhylo` object, or NULL if no tree file exists or
#'   parsing failed.
#' @keywords internal
.LoadTrees <- function(scenario, gridTag, repID, modelID, run) {
  gz <- TreeGzFile(scenario, gridTag, repID, modelID, run)
  tr <- sub("\\.tar\\.gz$", ".trees", gz)

  if (file.exists(gz)) {
    tmp <- tempfile(fileext = ".trees", tmpdir = TmpDir())
    on.exit(unlink(tmp), add = TRUE)
    system(paste("tar -xzf", shQuote(gz), "-O >", shQuote(tmp)))
    tryCatch(ape::read.tree(tmp), error = function(e) NULL)
  } else if (file.exists(tr)) {
    tryCatch(ape::read.tree(tr), error = function(e) NULL)
  } else {
    NULL
  }
}

#' Average Standard Deviation of Split Frequencies
#'
#' Computes the mean absolute difference in clade posterior probabilities
#' between two independent runs (Lakner et al. 2008). Values < ASDSF_MAX
#' indicate topological convergence.
#'
#' FIX: now takes pre-loaded tree lists (via `treesList`) instead of
#' re-extracting tree files itself — extraction is shared with
#' ComputeTreeESS() via .LoadTrees(), called once per run from
#' CheckConvergence(). Falls back to loading trees itself if
#' `treesList` is not supplied, so this remains independently callable.
#'
#' @inheritParams ComputeRhat
#' @param treesList Optional list of length nRuns of pre-loaded
#'   `multiPhylo` objects (see .LoadTrees()). If NULL, trees are loaded
#'   internally.
#' @return Scalar ASDSF value.
#' @export
ComputeASDSF <- function(scenario, gridTag, repID, modelID, nRuns = 2,
                          treesList = NULL) {
  if (nRuns != 2) stop("ASDSF requires exactly 2 runs")

  if (is.null(treesList)) {
    treesList <- lapply(1:2, function(run) {
      .LoadTrees(scenario, gridTag, repID, modelID, run)
    })
  }

  if (any(vapply(treesList, is.null, logical(1)))) {
    warning("Missing tree file for ", modelID, " ", gridTag, " ", repID)
    return(NA_real_)
  }

  trees1 <- treesList[[1]]
  trees2 <- treesList[[2]]

  .CladFreq <- function(trees) {
    splits <- lapply(trees, function(tr) ape::prop.part(tr))
    tab <- table(unlist(lapply(splits, function(sp) {
      vapply(sp, paste, character(1), collapse = ",")
    })))
    tab / length(trees)
  }

  freq1 <- .CladFreq(trees1)
  freq2 <- .CladFreq(trees2)

  allSplits <- union(names(freq1), names(freq2))
  f1 <- freq1[allSplits]; f1[is.na(f1)] <- 0
  f2 <- freq2[allSplits]; f2[is.na(f2)] <- 0

  mean(abs(f1 - f2))
}



# --- Distance-based tree topology ESS (with safety timeout) -----------------

#' Run an expression with a wall-clock timeout
#'
#' Uses R's built-in setTimeLimit() via a tryCatch on the "reached elapsed
#' time limit" condition. If the expression does not complete within
#' `seconds`, returns NA via the supplied `on_timeout` value instead of
#' hanging the whole batch.
#'
#' @param expr        Expression to evaluate.
#' @param seconds     Wall-clock timeout in seconds.
#' @param on_timeout  Value to return if the timeout is hit.
#' @keywords internal
.WithTimeout <- function(expr, seconds, on_timeout = NA_real_) {
  result <- on_timeout
  withCallingHandlers(
    tryCatch({
      setTimeLimit(elapsed = seconds, transient = TRUE)
      result <- expr
      setTimeLimit() # reset
      result
    }, error = function(e) {
      setTimeLimit() # always reset, even on error
      if (grepl("reached elapsed time limit|reached CPU time limit",
                conditionMessage(e))) {
        warning("ComputeTreeESS: timed out after ", seconds,
                "s — skipping this run (tree_ess = NA)")
      } else {
        warning("ComputeTreeESS: error — ", conditionMessage(e))
      }
      on_timeout
    }),
    warning = function(w) invokeRestart("muffleWarning")
  )
}

#' Distance-based tree topology ESS
#'
#' Estimates ESS for tree topology by computing pairwise CID distances across
#' the posterior sample, then applying Geyer's autocorrelation ESS estimator
#' to the mean distance series. Pools across runs by summing independent ESS
#' values, consistent with ComputeESS().
#'
#' A low tree_ess relative to scalar parameter ESS suggests the move schedule
#' is not proposing topology changes frequently enough. A high tree_ess with
#' low scalar ESS suggests the converse.
#'
#' SAFETY: the pairwise distance computation is O(n^2) in the number of
#' sampled trees and can stall on runs with very large posterior samples or
#' malformed tree files. Each run's computation is wrapped in a wall-clock
#' timeout (default 60s, set via TREE_ESS_TIMEOUT_SEC in _setup.R if defined,
#' else 60) so a single pathological run cannot block the whole batch.
#'
#' FIX: now takes pre-loaded tree lists (via `treesList`) instead of
#' re-extracting tree files itself — extraction is shared with
#' ComputeASDSF() via .LoadTrees(), called once per run from
#' CheckConvergence(). Falls back to loading trees itself if
#' `treesList` is not supplied, so this remains independently callable.
#'
#' @inheritParams ComputeRhat
#' @param timeoutSec Per-run wall-clock timeout in seconds (default 60).
#' @param treesList Optional list of length nRuns of pre-loaded
#'   `multiPhylo` objects (see .LoadTrees()). If NULL, trees are loaded
#'   internally.
#' @return Scalar tree topology ESS (pooled across runs), or NA if tree files
#'   are missing or the computation timed out on all runs.
#' @export
ComputeTreeESS <- function(scenario, gridTag, repID, modelID, nRuns = 2,
                            timeoutSec = if (exists("TREE_ESS_TIMEOUT_SEC")) TREE_ESS_TIMEOUT_SEC else 60,
                            treesList = NULL) {
  .ESS1 <- function(x) {
    n  <- length(x)
    if (n < 4) return(NA_real_)
    ac <- acf(x, lag.max = n - 1, plot = FALSE)$acf[-1]
    pairs  <- ac[seq(1, length(ac) - 1, 2)] + ac[seq(2, length(ac), 2)]
    cutoff <- which(pairs < 0)[1]
    if (is.na(cutoff)) cutoff <- length(pairs)
    rho_sum <- 1 + 2 * sum(ac[seq_len(2 * cutoff - 1)])
    max(1, n / rho_sum)
  }

  .OneRun <- function(run) {
    trees <- if (!is.null(treesList)) treesList[[run]] else .LoadTrees(scenario, gridTag, repID, modelID, run)

    if (is.null(trees) || length(trees) < 4) return(NA_real_)

    # Cap the number of trees used for the O(n^2) distance matrix —
    # thin to at most MAX_TREES_FOR_DIST trees evenly spaced through the
    # posterior sample. This keeps runtime bounded on very long chains
    # while still capturing the autocorrelation structure.
    MAX_TREES_FOR_DIST <- if (exists("TREE_ESS_MAX_TREES")) TREE_ESS_MAX_TREES else 1000L
    if (length(trees) > MAX_TREES_FOR_DIST) {
      idx   <- round(seq(1, length(trees), length.out = MAX_TREES_FOR_DIST))
      trees <- trees[idx]
    }

    # Mean CID distance from each tree to all others — scalar series over time
    dmat    <- TreeDist::ClusteringInfoDistance(trees)
    mn_dist <- rowMeans(as.matrix(dmat))
    .ESS1(mn_dist)
  }

  ess_per_run <- vapply(seq_len(nRuns), function(run) {
    .WithTimeout(.OneRun(run), seconds = timeoutSec, on_timeout = NA_real_)
  }, numeric(1))

  if (all(is.na(ess_per_run))) return(NA_real_)
  sum(ess_per_run, na.rm = TRUE)
}



# --- Combined check

#' Check convergence for one inference run
#'
#' Combines R-hat, ESS, ASDSF, and tree topology ESS into a single pass/fail
#' with a summary list. Writes a plain-text diagnostic file to
#' the-matrix/diagnostics/.
#'
#' @inheritParams ComputeRhat
#' @return Named list with elements:
#'   \item{pass}{Logical: TRUE if all three criteria met.}
#'   \item{rhat}{Named vector of R-hat values.}
#'   \item{ess}{Named vector of scalar parameter ESS values.}
#'   \item{tree_ess}{Scalar tree topology ESS (pooled across runs).}
#'   \item{asdsf}{Scalar ASDSF.}
#'   \item{rhat_pass}{Logical: max R-hat < RHAT_MAX.}
#'   \item{ess_pass}{Logical: min ESS > ESS_MIN.}
#'   \item{asdsf_pass}{Logical: ASDSF < ASDSF_MAX.}
#' @export
CheckConvergence <- function(scenario, gridTag, repID, modelID, nRuns = 2) {
  rhat <- ComputeRhat(scenario, gridTag, repID, modelID, nRuns)
  ess  <- ComputeESS( scenario, gridTag, repID, modelID, nRuns)

  # Load tree files once and share across ASDSF and TreeESS — previously
  # each function extracted the .tar.gz independently (2x the tar/IO cost
  # per replicate), and neither cleaned up its tempfile, which had
  # accumulated to 45GB / ~24k orphaned files under TmpDir()
  # and was degrading filesystem performance for the whole batch.
  treesList <- lapply(seq_len(nRuns), function(run) {
    .LoadTrees(scenario, gridTag, repID, modelID, run)
  })

  asdsf    <- ComputeASDSF(  scenario, gridTag, repID, modelID, nRuns, treesList = treesList)
  tree_ess <- ComputeTreeESS(scenario, gridTag, repID, modelID, nRuns, treesList = treesList)

  rhat_pass  <- !is.null(rhat)  && max(rhat,  na.rm = TRUE) < RHAT_MAX
  ess_pass   <- !is.null(ess)   && min(ess,   na.rm = TRUE) > ESS_MIN
  asdsf_pass <- !is.na(asdsf)   && asdsf < ASDSF_MAX
  pass       <- rhat_pass && ess_pass && asdsf_pass

  result <- list(
    pass       = pass,
    rhat       = rhat,
    ess        = ess,
    tree_ess   = tree_ess,
    asdsf      = asdsf,
    rhat_pass  = rhat_pass,
    ess_pass   = ess_pass,
    asdsf_pass = asdsf_pass
  )

  # Write plain-text diagnostic file to the-matrix/diagnostics/
  diagPath <- DiagFile(scenario, gridTag, repID, modelID)
  writeLines(c(
    paste("model:   ", modelID),
    paste("grid:    ", gridTag),
    paste("rep:     ", repID),
    paste("pass:    ", pass),
    paste("rhat_max:", if (!is.null(rhat))   round(max(rhat, na.rm = TRUE), 4) else "NA"),
    paste("ess_min: ", if (!is.null(ess))    round(min(ess,  na.rm = TRUE), 1) else "NA"),
    paste("tree_ess:", if (!is.na(tree_ess)) round(tree_ess, 1)                else "NA"),
    paste("asdsf:   ", round(asdsf, 5))
  ), diagPath)

  result
}

#' Check convergence across all grid cells for one model
#'
#' @param scenario "nt" or "mk"
#' @param modelID  Model script name
#' @param grid     Parameter grid (default PARAM_GRID)
#' @param nRep     Replicates per cell (default N_REP)
#' @return Data frame with one row per replicate and convergence columns.
#' @export
ConvergenceSummary <- function(scenario, modelID,
                               grid = PARAM_GRID,
                               nRep = N_REP) {
  rows <- vector("list", nrow(grid) * nRep)
  k    <- 1L

  for (gi in seq_len(nrow(grid))) {
    gridTag <- GridTag(grid[gi, ])
    for (rep in seq_len(nRep)) {
      repID  <- SimID(rep)
      result <- CheckConvergence(scenario, gridTag, repID, modelID)
      rows[[k]] <- data.frame(
        scenario   = scenario,
        gridTag    = gridTag,
        repID      = repID,
        modelID    = modelID,
        pass       = result$pass,
        rhat_max   = if (!is.null(result$rhat))   max(result$rhat, na.rm = TRUE) else NA_real_,
        ess_min    = if (!is.null(result$ess))     min(result$ess,  na.rm = TRUE) else NA_real_,
        tree_ess   = if (!is.na(result$tree_ess))  result$tree_ess                else NA_real_,
        asdsf      = result$asdsf,
        stringsAsFactors = FALSE
      )
      k <- k + 1L
    }
  }

  do.call(rbind, rows)
}
