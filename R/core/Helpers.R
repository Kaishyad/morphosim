# removes the first `burnin` samples (fraction or count) from a series
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

# converts seconds to slurm's d-h:m:s format
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

# number of characters with a non-ambiguous state
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
    read.table(x, header = TRUE, colClasses = rep("numeric", 5)),
    warning = function(w) {
      res <- withCallingHandlers(
        read.table(x, header = TRUE),
        warning = function(w) invokeRestart("muffleWarning")
      )
      res[!apply(is.na(res), 1, any), ]
    }, error = function(e) {
      msg <- e[["message"]]

      if (msg == "scan() expected 'a real', got 'Iteration'") {
        read.table(x, header = TRUE)
      } else {
        nrows <- as.numeric(sub(".*?(\\d+).*", "\\1", msg, perl = TRUE)) - 2
        tryCatch(read.table(x, header = TRUE, nrows = nrows),
                 error = function(e) {
                   stop("Error reading ", x, ":\r\n ", e)
                 })
      }
    }
  )
}

#has an analysis converged? adapted from neotrans (smith, 2026), used
#directly instead of the newer checkconvergence() in convergence.r
HasConverged <- function(pID, scriptID,
                         pt = .config$psrfThreshold,
                         et = .config$essThreshold) {
  convFile <- ConvergenceFile(pID, scriptID)
  if (!file.exists(convFile)) {
    return(structure(FALSE, reason = "No convergence file; UpdateRecords()?"))
  }
  convStats <- read.table(ConvergenceFile(pID, scriptID))
  conv <- c(psrf    = convStats[["psrf"]]                < pt,
            ess     = convStats[["ess"]]                  > et,
            frechet = convStats[["frechetCorrelationESS"]] > et,
            median  = convStats[["medianPseudoESS"]]       > et)
  structure(all(conv), stats = convStats, atThreshold = conv)
}
