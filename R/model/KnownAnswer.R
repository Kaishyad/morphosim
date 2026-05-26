# R/KnownAnswer.R
# Simulation-based calibration (Cook, Gelman & Rubin 2006).
# Verifies that the 95% posterior credible interval contains the known true
# parameter value in approximately 95% of replicates across the parameter grid.
# Applied to tree_length and gain-to-loss rate ratio (rate_loss) under the
# NT generative model with Model 4 (sp_nt_kv) or Model 8 (full NT+RH).

# Used in: analysis/known_answer.R
# Dissertation section: 6.1 Correctness

#' Extract posterior credible interval for a named parameter
#'
#' Reads the stochastic-only .p.log file for a replicate, pools both runs,
#' and returns the 2.5th and 97.5th percentiles.
#'
#' @param scenario  "nt" or "mk"
#' @param gridTag   Grid tag string from GridTag()
#' @param repID     Replicate ID e.g. "sim001"
#' @param modelID   Model script name e.g. "model4"
#' @param parameter Column name in the log file e.g. "tree_length"
#' @param nRuns     Number of MCMC runs (default 2)
#' @param burnFrac  Fraction of samples to discard as burnin (default 0.1)
#' @return Numeric vector of length 2: c(lower, upper) credible interval bounds,
#'   or NULL if the log file does not exist.
#' @export
CredibleInterval <- function(scenario, gridTag, repID, modelID,
                             parameter, nRuns = 2, burnFrac = 0.1) {
  samples <- unlist(lapply(seq_len(nRuns), function(run) {
    f <- LogFile(scenario, gridTag, repID, modelID, run)
    if (!file.exists(f)) return(NULL)
    log <- read.table(f, header = TRUE, comment.char = "#")
    if (!parameter %in% colnames(log)) {
      warning(parameter, " not found in log for ", modelID, " ", repID)
      return(NULL)
    }
    n <- nrow(log)
    log[[parameter]][seq(floor(n * burnFrac) + 1L, n)]
  }))
  
  if (is.null(samples) || length(samples) == 0) return(NULL)
  quantile(samples, c(0.025, 0.975))
}

#' Test whether a credible interval contains the true value
#'
#' @param ci        Numeric vector of length 2 from CredibleInterval()
#' @param trueValue Known true parameter value from the simulation design
#' @return Logical TRUE if trueValue falls within ci, FALSE otherwise, NA if ci is NULL
#' @export
CoversTrue <- function(ci, trueValue) {
  if (is.null(ci)) return(NA)
  ci[[1]] <= trueValue && trueValue <= ci[[2]]
}

#' Empirical coverage rate across replicates in one grid cell
#'
#' @param scenario  "nt" or "mk"
#' @param gridTag   Grid tag from GridTag()
#' @param modelID   Model script name
#' @param parameter Parameter name in log file
#' @param trueValue Known true value (scalar from grid row)
#' @param nRep      Number of replicates
#' @return Scalar proportion of replicates where CI covers trueValue
#' @export
CoverageRate <- function(scenario, gridTag, modelID,
                         parameter, trueValue,
                         nRep = N_REP) {
  covers <- vapply(seq_len(nRep), function(rep) {
    repID <- SimID(rep)
    ci    <- CredibleInterval(scenario, gridTag, repID, modelID, parameter)
    CoversTrue(ci, trueValue)
  }, logical(1))
  
  mean(covers, na.rm = TRUE)
}

#' Known-answer summary across all grid cells
#'
#' Tests coverage of tree_length and rate_loss (gain-to-loss ratio) under
#' the NT generative scenario. Both parameters have known true values from
#' the simulation design (tree_length from grid row; rate_loss = 1/gain_loss).
#'
#' @param modelID  Model to evaluate (should be model4 or model8)
#' @param grid     Parameter grid (default PARAM_GRID)
#' @param nRep     Replicates per cell (default N_REP)
#' @return Data frame with coverage rates and MSE for both focal parameters
#'   across all grid cells.
#' @export
KnownAnswerSummary <- function(modelID = "model4",
                               grid    = PARAM_GRID,
                               nRep    = N_REP) {
  rows <- vector("list", nrow(grid))
  
  for (gi in seq_len(nrow(grid))) {
    row     <- grid[gi, ]
    gridTag <- GridTag(row)
    
    # True parameter values as fixed by the simulation design
    trueTreeLen  <- row$tree_length
    trueRateLoss <- 1 / row$gain_loss  # rate_loss = 1 / gain_loss in sim scripts
    
    covTreeLen  <- CoverageRate("nt", gridTag, modelID,
                                "tree_length", trueTreeLen, nRep)
    covRateLoss <- CoverageRate("nt", gridTag, modelID,
                                "rate_loss",   trueRateLoss, nRep)
    
    # Mean squared error of posterior mean vs true value
    .MSE <- function(parameter, trueVal) {
      postMeans <- vapply(seq_len(nRep), function(rep) {
        repID <- SimID(rep)
        f <- LogFile("nt", gridTag, repID, modelID, run = 1)
        if (!file.exists(f)) return(NA_real_)
        log <- read.table(f, header = TRUE, comment.char = "#")
        if (!parameter %in% colnames(log)) return(NA_real_)
        n   <- nrow(log)
        samples <- log[[parameter]][seq(floor(n * 0.1) + 1L, n)]
        mean(samples, na.rm = TRUE)
      }, numeric(1))
      mean((postMeans - trueVal)^2, na.rm = TRUE)
    }
    
    rows[[gi]] <- data.frame(
      gridTag      = gridTag,
      tree_length  = trueTreeLen,
      gain_loss    = row$gain_loss,
      n_char       = row$n_char,
      cov_tree_len = covTreeLen,
      cov_rate_loss= covRateLoss,
      mse_tree_len = .MSE("tree_length", trueTreeLen),
      mse_rate_loss= .MSE("rate_loss",   trueRateLoss),
      stringsAsFactors = FALSE
    )
  }
  
  do.call(rbind, rows)
}

#' Prior vs posterior visualisation for a single replicate
#'
#' Plots posterior density against the lognormal prior for a named parameter.
#' Adapted from PriorVsPost() (supervisor / neotrans Posterior.R).
#' The supervisor's version used ParameterFile() and project IDs; this version
#' reads directly from the-matrix log files via LogFile().
#'
#' @param scenario  "nt" or "mk"
#' @param gridTag   Grid tag
#' @param repID     Replicate ID
#' @param modelID   Model script name
#' @param parameter Parameter column name (e.g. "rate_loss", "rate_neo")
#' @param priorMean Mean of lognormal prior on the log scale (default 0)
#' @param priorSD   SD of lognormal prior on the log scale (default 2)
#' @export
PriorVsPost <- function(scenario, gridTag, repID, modelID,
                        parameter  = "rate_loss",
                        priorMean  = 0,
                        priorSD    = 2) {
  samples <- unlist(lapply(1:2, function(run) {
    f <- LogFile(scenario, gridTag, repID, modelID, run)
    if (!file.exists(f)) return(NULL)
    log <- read.table(f, header = TRUE, comment.char = "#")
    n   <- nrow(log)
    log[[parameter]][seq(floor(n * 0.1) + 1L, n)]
  }))
  
  if (is.null(samples)) {
    stop("No log file found for ", modelID, " ", gridTag, " ", repID)
  }
  
  quants <- quantile(samples, c(0.01, 0.99))
  xrange <- c(min(exp(priorMean - 3 * priorSD), quants[[1]]),
              max(exp(priorMean + 3 * priorSD), quants[[2]]))
  grid_x  <- seq(xrange[[1]], xrange[[2]], length.out = 2000)
  priorY  <- dlnorm(grid_x, priorMean, priorSD)
  
  postD <- density(samples, from = xrange[[1]], to = xrange[[2]])
  ylim  <- range(c(postD$y, priorY))
  
  plot(postD, frame.plot = FALSE, main = paste(modelID, parameter),
       xlim = xrange, ylim = ylim,
       xlab = parameter, ylab = "Density",
       col = "#0072B2", lwd = 2)
  lines(grid_x, priorY, col = "#D55E00", lwd = 2, lty = 2)
  legend("topright", bty = "n", lwd = 2, lty = c(1, 2),
         col = c("#0072B2", "#D55E00"),
         legend = c("Posterior", "Prior"))
}