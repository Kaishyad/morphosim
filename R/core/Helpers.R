#Update for the project

#' Remove burnin
#' @param values series of parameter estimates
#' @param burnin fraction or number of samples to omit from start
#' @return `BurnOff()` returns `values`, without the first `burnin` samples
#' @export
BurnOff <- function(values, burnin) {
  .Keep <- function(n, burnin) {
    (if (burnin < 1) n * burnin else burnin):n
  }
  if (is.null(dim(values))) {
    values[.Keep(length(values), burnin)]
  } else {
    values[.Keep(dim(values)[[1]], burnin), ]
  }
}

#' Convert time to H:M:S format
#' @param secs time period in seconds
#' @return Time period formatted for SLURM
#' @export
AsHMS <- function(secs) {
  d <- secs %/% (24 * 3600)
  h <- secs %% (24 * 3600) %/% 3600
  m <- secs %% 3600 %/% 60
  s <- secs %% 60
  paste(if (d > 0) sprintf("%d-", d),
        sprintf("%02d:%02d:%02d", as.integer(h), as.integer(m), as.integer(s)),
        sep = "")
}

.ColourBy <- function(x, palette = "inferno") {
  n <- 512
  hcl.colors(n, palette = palette)[cut(x, n)]
}

#' @importFrom PlotTools SpectrumLegend
.LegendBy <- function(x, palette = "inferno", where = "topleft", label = NULL) {
  SpectrumLegend(
    where,
    bty = "n",
    xpd = NA,
    palette = hcl.colors(48, palette = palette),
    legend = signif(seq(max(x, na.rm = TRUE), min(x, na.rm = TRUE),
                        length.out = 5), 4),
    title = label
  )
}

.NChar <- function(path) {
  if (file.exists(path)) {
    as.integer(
      gsub(".*NCHAR\\s*=\\s*(\\d+)\\D.*", "\\1", readLines(path, 3)[[3]])
    )
  } else {
    warning("No file at ", path)
    NA_integer_
  }
}

.NTaxa <- function(path) {
  if (file.exists(path)) {
    as.integer(
      gsub(".*NTAX\\s*=\\s*(\\d+)\\D.*", "\\1", readLines(path, 3)[[3]])
    )
  } else {
    warning("No file at ", path)
    NA_integer_
  }
}

#' Number of characters with non-ambiguous state
#' @param path Path to nexus file
#' @export
.NCoded <- function(path) {
  if (file.exists(path)) {
    sum(ReadCharacters(path) %in% 0:9)
  } else {
    warning("No file at ", path)
    NA_integer_
  }
}

.ReadTable <- function(x) {
  tryCatch(
    res <- read.table(x, header = TRUE, colClasses = rep("real", 5)),
    warning = function(w) {
      res <- withCallingHandlers(
        read.table(x, header = TRUE),
        warning = function(w) invokeRestart("muffleWarning")
      )
      res[!apply(is.na(res), 1, any), ]
    }, error = function(e) {
      msg <- e[["message"]]
      
      if (msg ==  "scan() expected 'a real', got 'Iteration'") {
        read.table(x, header = TRUE)
      } else {
        nrows <- as.numeric(sub(".*?(\\d+).*", "\\1", msg, perl = TRUE)) - 2
        # Why 2, not 1? I don't know!
        #  Sometimes nrows = 10 fails with "line 11 didn't have enough elements"
        tryCatch(read.table(x, header = TRUE, nrows = nrows),
                 error = function(e) {
                   stop("Error reading ", x, ":\r\n ", e)
                 })
      }
    }
  )
}


#' Has an analysis converged?
#' @param pt Gelman-Rubin statistic (potential scale reduction factor) threshold;
#' analyses with PSRF > `pt` have not converged.
#' @param et Estimated sample size threshold; analyses with ESS < `et` have
#' not converged.
#' @inheritParams MakeSlurm
#' @returns `HasConverged()` returns a logical specifying whether the specified
#' analysis has converged at the specified thresholds.
#' @export
HasConverged <- function(pID, scriptID, pt = .config$psrfThreshold, et = .config$essThreshold) {
  convFile <- ConvergenceFile(pID, scriptID)
  if (!file.exists(convFile)) {
    return(structure(FALSE, reason = "No convergence file; UpdateRecords()?"))
  }
  convStats <- read.table(ConvergenceFile(pID, scriptID))
  conv <- c(psrf = convStats[["psrf"]] < pt,
            ess = convStats[["ess"]] > et,
            frechet = convStats[["frechetCorrelationESS"]] > et,
            median = convStats[["medianPseudoESS"]] > et)
  # Return:
  structure(all(conv),
            stats = convStats,
            atThreshold = conv)
}
