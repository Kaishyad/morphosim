# simulation-based calibration (cook, gelman & rubin 2006)

# maps a model id to its logged gain/loss rate parameter column(s)
RateLossParams <- function(modelID) {
  switch(modelID,
    model1  = character(0),
    model2  = "gain_loss_ratio",
    model3  = "gain_loss_ratio",
    c("gain_loss_neo", "gain_loss_trans")  # default: all two-partition models
  )
}

# reads the stochastic-only .p.log file for a replicate, pools both runs,
# and returns the 2.5th/97.5th percentiles as the credible interval
CredibleInterval <- function(scenario, gridTag, repID, modelID,
                             parameter, nRuns = 2, burnFrac = 0.1) {
  samples <- unlist(lapply(seq_len(nRuns), function(run) {
    f <- ParamLogFile(scenario, gridTag, repID, modelID, run)
    if (!file.exists(f)) return(NULL)
    log <- read.table(f, header = TRUE, comment.char = "#", fill = TRUE)
    if (!parameter %in% colnames(log)) {
      warning(parameter, " not found in log for ", modelID, " ", repID)
      return(NULL)
    }
    n <- nrow(log)
    log[[parameter]][seq(floor(n * burnFrac) + 1L, n)]
  }))

  if (is.null(samples) || length(samples) == 0) return(NULL)
  quantile(samples, c(0.025, 0.975), na.rm = TRUE)
}

# does a credible interval contain the true value?
CoversTrue <- function(ci, trueValue) {
  if (is.null(ci)) return(NA)
  ci[[1]] <= trueValue && trueValue <= ci[[2]]
}

# empirical coverage rate across replicates in one grid cell
CoverageRate <- function(scenario, gridTag, modelID,
                         parameter, trueValue,
                         nRep = N_REP) {
  covers <- vapply(seq_len(nRep), function(rep) {
    repID <- SimID(rep)
    ci  <- CredibleInterval(scenario, gridTag, repID, modelID, parameter)
    CoversTrue(ci, trueValue)
  }, logical(1))

  mean(covers, na.rm = TRUE)
}

# known-answer summary across all grid cells. true values come from the
# simulation design: tree_length = grid row value, rate_loss = 1 / gain_loss
KnownAnswerSummary <- function(modelID = "model1", scenario = "mk", grid = ScenarioGrid(scenario), nRep = N_REP) {
  rows <- vector("list", nrow(grid))
  rateLossCols <- RateLossParams(modelID)

  # mean squared error of posterior mean vs true value
  .MSE <- function(scenario, gridTag, modelID, parameter, trueVal, nRep) {
    postMeans <- vapply(seq_len(nRep), function(rep) {
      repID <- SimID(rep)
      f <- ParamLogFile(scenario, gridTag, repID, modelID, run = 1)
      if (!file.exists(f)) return(NA_real_)
      log <- read.table(f, header = TRUE, comment.char = "#", fill = TRUE)
      if (!parameter %in% colnames(log)) return(NA_real_)
      n       <- nrow(log)
      samples <- log[[parameter]][seq(floor(n * 0.1) + 1L, n)]
      mean(samples, na.rm = TRUE)
    }, numeric(1))
    mean((postMeans - trueVal)^2, na.rm = TRUE)
  }

  for (gi in seq_len(nrow(grid))) {
    row     <- grid[gi, ]
    gridTag <- GridTag(row)

    trueTreeLen  <- row$tree_length
    trueRateLoss <- 1 / row$gain_loss  # rate_loss = 1 / gain_loss in sim scripts

    covTreeLen <- CoverageRate(scenario, gridTag, modelID,
                               "tree_length", trueTreeLen, nRep)
    mseTreeLen <- .MSE(scenario, gridTag, modelID,
                       "tree_length", trueTreeLen, nRep)

    baseRow <- data.frame(
      gridTag       = gridTag,
      tree_length   = trueTreeLen,
      gain_loss     = row$gain_loss,
      n_char        = row$n_char,
      cov_tree_len  = covTreeLen,
      mse_tree_len  = mseTreeLen,
      stringsAsFactors = FALSE
    )

    if (length(rateLossCols) == 0L) {
      # model1: no free rate parameter to test (fixed fnJC symmetric Q)
      baseRow$rate_param    <- NA_character_
      baseRow$cov_rate_loss <- NA_real_
      baseRow$mse_rate_loss <- NA_real_
      rows[[gi]] <- baseRow
    } else {
      # one row per logged rate-parameter column (1 for single-partition
      # asymmetric models, 2 for two-partition models)
      perParam <- lapply(rateLossCols, function(col) {
        r <- baseRow
        r$rate_param    <- col
        r$cov_rate_loss <- CoverageRate(scenario, gridTag, modelID,
                                        col, trueRateLoss, nRep)
        r$mse_rate_loss <- .MSE(scenario, gridTag, modelID,
                                col, trueRateLoss, nRep)
        r
      })
      rows[[gi]] <- do.call(rbind, perParam)
    }
  }

  do.call(rbind, rows)
}

# prior vs posterior visualisation for a single replicate
PriorVsPost <- function(scenario, gridTag, repID, modelID,
                        parameter  = "rate_loss",
                        priorMean  = 0,
                        priorSD    = 2) {
  samples <- unlist(lapply(1:2, function(run) {
    f <- ParamLogFile(scenario, gridTag, repID, modelID, run)
    if (!file.exists(f)) return(NULL)
    log <- read.table(f, header = TRUE, comment.char = "#", fill = TRUE)
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
