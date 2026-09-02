# spearman rho between two ranked/numeric vectors, with bootstrap ci, used to
# check whether tree accuracy predicts the other metrics (convergence, known-answer, cgr)

# spearman rank correlation (spearman, 1904) with a percentile bootstrap
# 95% ci (efron, 1979), b = 1000 by default
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

  # resample pairs jointly, percentile ci (efron, 1979)
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
