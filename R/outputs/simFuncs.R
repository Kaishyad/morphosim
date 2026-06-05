# Visualisation helper for exploratory runs.
# PlotParamViolin() produces violin plots of posterior parameter medians
# (rate_loss, rate_neo, tree_length) on a log-scale y-axis with true-value markers.
#
# NOTE: QueueSim(), SimTrees(), FetchLogIfMissing(), PackageFile() have been
# removed. They were carried over from the legacy neotrans SSH workflow and
# referenced undefined functions (SshSession, MkPath, SlurmQueue, scp_download)
# that don't exist in this codebase. Job submission is now handled by
# run/submit_inference.R via .WriteSlurmScript().


#' Violin plot of posterior parameter medians with exp-scale y-axis
#'
#' Plots log-transformed posterior medians for rate_loss, rate_neo, and
#' tree_length as violins, with the y-axis labelled on the original
#' (non-log-transformed) scale.
#'
#' @param loss,neo,lng Summary matrices (rows = summary stats, cols = replicates)
#'   as returned by \code{sapply(..., summary)}.
#' @param true_vals Named numeric vector of true simulation values, in order
#'   \code{c(n, t, length)}.
#' @export
PlotParamViolin <- function(loss, neo, lng, true_vals) {
  vioplot::vioplot(
    log(loss["Median", ]), log(neo["Median", ]), log(lng["Median", ]),
    names = c("", "", ""),
    col = 5:3,
    axes = FALSE,
    xaxt = "n",
    yaxt = "n",
    frame.plot = FALSE
  )
  axis(1, at = 1:3,
       labels = expression(italic(n), italic(t), "tree length"),
       las = 1, lty = 0)
  log_ticks <- pretty(range(log(c(loss["Median", ], neo["Median", ],
                                  lng["Median", ]))))
  axis(2, at = log_ticks, labels = round(exp(log_ticks), 2), las = 2)
  abline(h = 0, lty = "dashed", col = "#888888")
  points(1:3, log(true_vals), pch = 95, cex = 2, col = 2, lwd = 3)
  points(1:3, c(median(log(loss["Median", ])),
                median(log(neo["Median", ])),
                median(log(lng["Median", ]))),
         pch = 20, cex = 0.8, col = "white")
}

# Count number of binary characters with informative pattern
#' @export
NInformative <- function(...) {
  sum(colSums(apply(PhyDatToMatrix(ReadAsPhyDat(file.path(...))), 2, table) < 2) == 0)
}
