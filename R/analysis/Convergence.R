#mcmc convergence diagnostics for inference runs:
#rank-normalised r-hat < RHAT_MAX, ess > ESS_MIN for all continuous
#parameters, asdsf < ASDSF_MAX across paired tree files

# rank-normalised split r-hat (vehtari et al. 2021). reads the .p.log file
# for each run, splits each chain's samples in half, rank-normalises all
# splits, then computes the standard gelman-rubin variance ratio - catches
# convergence failures in heavy-tailed posteriors that plain psrf can miss.
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

  # drop iteration column; keep only numeric parameters
  params <- intersect(colnames(logs[[1]]), colnames(logs[[2]]))
  params <- params[params != "Iteration"]

  # rank-normalise: convert each chain's samples to normal scores
  .RankNorm <- function(x) {
    r <- rank(x, ties.method = "average")
    qnorm((r - 0.375) / (length(r) + 0.25))
  }

  # split each run in half to create 2*nRuns chains
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

# effective sample size per parameter, via the autocorrelation-based
# estimator; flags parameters below ESS_MIN
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
    # geyer's initial positive sequence estimator
    pairs   <- ac[seq(1, length(ac) - 1, 2)] + ac[seq(2, length(ac), 2)]
    cutoff  <- which(pairs < 0)[1]
    if (is.na(cutoff)) cutoff <- length(pairs)
    rho_sum <- 1 + 2 * sum(ac[seq_len(2 * cutoff - 1)])
    max(1, n / rho_sum)
  }

  # pool ess across runs (sum of independent ess values)
  vapply(params, function(p) {
    ess_per_run <- vapply(logs, function(log) .ESS1(log[[p]]), numeric(1))
    sum(ess_per_run)
  }, numeric(1))
}

# loads posterior tree samples for one run. extracted tempfiles under
# TmpDir() are always removed on exit.
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

# average standard deviation of split frequencies (lakner et al. 2008): mean
# absolute difference in clade posterior probabilities between two
# independent runs. values < ASDSF_MAX indicate topological convergence.
# takes pre-loaded tree lists via treesList (shared with ComputeTreeESS from
# CheckConvergence()), or loads trees itself if treesList is NULL.
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

# runs an expression with a wall-clock timeout
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

# distance-based tree topology ess. estimates ess for tree topology by
# computing pairwise cid distances across the posterior sample, then
# applying geyer's autocorrelation ess estimator to the mean distance
# series; pools across runs by summing independent ess values, consistent
# with ComputeESS(). pairwise distance computation is O(n^2), so each run is
# wrapped in a wall-clock timeout.
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

    # cap trees used for the O(n^2) distance matrix, evenly spaced
    MAX_TREES_FOR_DIST <- if (exists("TREE_ESS_MAX_TREES")) TREE_ESS_MAX_TREES else 1000L
    if (length(trees) > MAX_TREES_FOR_DIST) {
      idx   <- round(seq(1, length(trees), length.out = MAX_TREES_FOR_DIST))
      trees <- trees[idx]
    }

    # mean cid distance from each tree to all others
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

# checks convergence for one inference run: combines r-hat, ess, asdsf, and
# tree topology ess into a single pass/fail with a summary list, and writes
# a diagnostic file to the-matrix/diagnostics/
CheckConvergence <- function(scenario, gridTag, repID, modelID, nRuns = 2) {
  rhat <- ComputeRhat(scenario, gridTag, repID, modelID, nRuns)
  ess  <- ComputeESS( scenario, gridTag, repID, modelID, nRuns)

  # load tree files once, shared across asdsf and tree ess
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
    pass    = pass,
    rhat= rhat,
    ess= ess,
    tree_ess   = tree_ess,
    asdsf= asdsf,
    rhat_pass  = rhat_pass,
    ess_pass   = ess_pass,
    asdsf_pass = asdsf_pass
  )

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

# checks convergence across all grid cells for one model; one row per
# replicate with convergence columns
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
