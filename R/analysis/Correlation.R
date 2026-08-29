#spearman rho between two ranked/numeric vectors, w/ bootstrap CI to check whether tree accuracy predicts the other metrics (convergence, known-answer, CGR)

#' Compute Spearman's rho with a bootstrap CI
#' Spearman rank correlation (Spearman, 1904) between two paired vectors,
#' with a percentile bootstrap 95% CI (Efron, 1979), B = 1000 by default.
#'
#' @param cid_vec    Numeric vector (typically median CID per grid cell).
#' @param acc_vec    Numeric vector to correlate against cid_vec.
#' @param B          Number of bootstrap resamples (default 1000).
#' @param conf       Confidence level for CI (default 0.95).
#' @return Named list:
#'   \item{rho}{Observed Spearman's rho.}
#'   \item{lower}{Lower bootstrap CI bound.}
#'   \item{upper}{Upper bootstrap CI bound.}
#'   \item{p.value}{Two-sided p-value from cor.test().}
#'   \item{n}{Number of complete pairs used.}
#' @importFrom stats cor.test
#' @export
SpearmanCorrelation <- function(cid_vec, acc_vec, B = 1000L, conf = 0.95) {
  # drop pairs where either side is NA
  keep     <- !is.na(cid_vec) & !is.na(acc_vec)
  cid_vec  <- cid_vec[keep]
  acc_vec  <- acc_vec[keep]
  n        <- length(cid_vec)
  
  if (n < 5L) {
    warning("Fewer than 5 complete pairs; returning NA")
    return(list(rho = NA_real_, lower = NA_real_,
                upper = NA_real_, p.value = NA_real_, n = n))
  }
  
  ct    <- cor.test(cid_vec, acc_vec, method = "spearman", exact = FALSE)
  rho   <- unname(ct$estimate)
  pval  <- ct$p.value
  
  # resample pairs jointly, percentile CI (Efron, 1979)
  set.seed(42L)
  rho_boot <- vapply(seq_len(B), function(i) {
    idx <- sample.int(n, n, replace = TRUE)
    suppressWarnings(
      cor(cid_vec[idx], acc_vec[idx], method = "spearman")
    )
  }, numeric(1))
  
  alpha <- (1 - conf) / 2
  ci    <- quantile(rho_boot, c(alpha, 1 - alpha), na.rm = TRUE)
  
  list(
    rho     = rho,
    lower   = unname(ci[[1]]),
    upper   = unname(ci[[2]]),
    p.value = pval,
    n       = n
  )
}
