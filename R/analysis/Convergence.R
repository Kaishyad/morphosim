# MCMC convergence diagnostics for inference runs.
# Called by analysis/check_convergence.R after Hamilton jobs complete.
#
# Three criteria must all pass before a run's results are used:
#   1. Rank-normalised R-hat < RHAT_MAX  (Vehtari et al. 2021)
#   2. ESS > ESS_MIN for all continuous parameters
#   3. ASDSF < ASDSF_MAX across paired tree files


# --- R-hat

#' Rank-normalised split R-hat (Vehtari et al. 2021)
#'
#' Reads the .p.log file for each run, splits each chain's samples in half,
#' rank-normalises all splits, then computes the standard Gelman-Rubin
#' variance ratio. Sensitive to convergence failures in heavy-tailed
#' posteriors that standard PSRF can miss.
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
    f <- LogFile(scenario, gridTag, repID, modelID, run)
    if (!file.exists(f)) return(NULL)
    read.table(f, header = TRUE, comment.char = "#")
  })
  
  if (any(vapply(logs, is.null, logical(1)))) {
    warning("Missing log file for ", modelID, " ", gridTag, " ", repID)
    return(NULL)
  }
  
  #Drop iteration column; keep only numeric parameters
  params <- intersect(colnames(logs[[1]]),
                      colnames(logs[[2]]))
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
    x   <- lapply(chains, function(ch) .RankNorm(ch[[p]]))
    m   <- length(x)
    n   <- length(x[[1]])
    B   <- n * var(vapply(x, mean, numeric(1)))
    W   <- mean(vapply(x, var, numeric(1)))
    sqrt(((n - 1) / n * W + B / n) / W)
  }, numeric(1))
}

# --- ESS 

#' Effective Sample Size per parameter
#'
#' Uses the autocorrelation-based ESS estimate. Flags parameters below
#' ESS_MIN (defined in _setup.R).
#'
#' @inheritParams ComputeRhat
#' @return Named numeric vector of ESS values.
#' @export
ComputeESS <- function(scenario, gridTag, repID, modelID, nRuns = 2) {
  logs <- lapply(seq_len(nRuns), function(run) {
    f <- LogFile(scenario, gridTag, repID, modelID, run)
    if (!file.exists(f)) return(NULL)
    read.table(f, header = TRUE, comment.char = "#")
  })
  
  if (any(vapply(logs, is.null, logical(1)))) {
    warning("Missing log file for ", modelID, " ", gridTag, " ", repID)
    return(NULL)
  }
  
  params <- setdiff(colnames(logs[[1]]), "Iteration")
  
  .ESS1 <- function(x) {
    n   <- length(x)
    ac  <- acf(x, lag.max = n - 1, plot = FALSE)$acf[-1]
    # Geyer's initial positive sequence estimator
    pairs <- ac[seq(1, length(ac) - 1, 2)] + ac[seq(2, length(ac), 2)]
    cutoff <- which(pairs < 0)[1]
    if (is.na(cutoff)) cutoff <- length(pairs)
    rho_sum <- 1 + 2 * sum(ac[seq_len(2 * cutoff - 1)])
    max(1, n / rho_sum)
  }
  
  # Pool ESS across runs using harmonic mean of individual ESS
  pooled <- vapply(params, function(p) {
    ess_per_run <- vapply(logs, function(log) .ESS1(log[[p]]), numeric(1))
    sum(ess_per_run)   # total ESS = sum across independent runs
  }, numeric(1))
  
  pooled
}

# ---ASDSF

#' Average Standard Deviation of Split Frequencies
#'
#' Computes the mean absolute difference in clade posterior probabilities
#' between two independent runs (Lakner et al. 2008). Values < ASDSF_MAX
#' indicate topological convergence.
#'
#' @inheritParams ComputeRhat
#' @return Scalar ASDSF value.
#' @export
ComputeASDSF <- function(scenario, gridTag, repID, modelID, nRuns = 2) {
  if (nRuns != 2) stop("ASDSF requires exactly 2 runs")
  
  treeFiles <- lapply(1:2, function(run) {
    gz <- TreeGzFile(scenario, gridTag, repID, modelID, run)
    tr <- sub("\\.tar\\.gz$", ".trees", gz)
    if (file.exists(gz)) {
      tmp <- tempfile(fileext = ".trees")
      system(paste("tar -xzf", shQuote(gz), "-O >", shQuote(tmp)))
      tmp
    } else if (file.exists(tr)) {
      tr
    } else {
      NULL
    }
  })
  
  if (any(vapply(treeFiles, is.null, logical(1)))) {
    warning("Missing tree file for ", modelID, " ", gridTag, " ", repID)
    return(NA_real_)
  }
  
  trees1 <- ape::read.tree(treeFiles[[1]])
  trees2 <- ape::read.tree(treeFiles[[2]])
  
  # Compute clade frequencies in each run
  .CladFreq <- function(trees) {
    splits <- lapply(trees, function(tr) {
      ape::prop.part(tr)
    })
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

# --- Combined check

#' Check convergence for one inference run
#'
#' Combines R-hat, ESS, and ASDSF into a single pass/fail with a summary list.
#' Writes a plain-text diagnostic file to the-matrix/diagnostics/.
#'
#' @inheritParams ComputeRhat
#' @return Named list with elements:
#'   \item{pass}{Logical: TRUE if all three criteria met.}
#'   \item{rhat}{Named vector of R-hat values.}
#'   \item{ess}{Named vector of ESS values.}
#'   \item{asdsf}{Scalar ASDSF.}
#'   \item{rhat_pass}{Logical: max R-hat < RHAT_MAX.}
#'   \item{ess_pass}{Logical: min ESS > ESS_MIN.}
#'   \item{asdsf_pass}{Logical: ASDSF < ASDSF_MAX.}
#' @export
CheckConvergence <- function(scenario, gridTag, repID, modelID, nRuns = 2) {
  rhat  <- ComputeRhat( scenario, gridTag, repID, modelID, nRuns)
  ess   <- ComputeESS(  scenario, gridTag, repID, modelID, nRuns)
  asdsf <- ComputeASDSF(scenario, gridTag, repID, modelID, nRuns)
  
  rhat_pass  <- !is.null(rhat)  && max(rhat,  na.rm = TRUE) < RHAT_MAX
  ess_pass   <- !is.null(ess)   && min(ess,   na.rm = TRUE) > ESS_MIN
  asdsf_pass <- !is.na(asdsf)   && asdsf < ASDSF_MAX
  pass       <- rhat_pass && ess_pass && asdsf_pass
  
  result <- list(
    pass       = pass,
    rhat       = rhat,
    ess        = ess,
    asdsf      = asdsf,
    rhat_pass  = rhat_pass,
    ess_pass   = ess_pass,
    asdsf_pass = asdsf_pass
  )
  
  # Write plain-text diagnostic file to the-matrix/diagnostics/
  diagPath <- DiagFile(scenario, gridTag, repID, modelID)
  writeLines(c(
    paste("model:  ", modelID),
    paste("grid:   ", gridTag),
    paste("rep:    ", repID),
    paste("pass:   ", pass),
    paste("rhat_max:", if (!is.null(rhat)) round(max(rhat, na.rm = TRUE), 4) else "NA"),
    paste("ess_min: ", if (!is.null(ess))  round(min(ess,  na.rm = TRUE), 1) else "NA"),
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
        rhat_max   = if (!is.null(result$rhat)) max(result$rhat, na.rm = TRUE) else NA_real_,
        ess_min    = if (!is.null(result$ess))  min(result$ess,  na.rm = TRUE) else NA_real_,
        asdsf      = result$asdsf,
        stringsAsFactors = FALSE
      )
      k <- k + 1L
    }
  }
  
  do.call(rbind, rows)
}

