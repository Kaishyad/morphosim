# Diagnostic: compare tree counts and per-stage timing across models
# Run from morphosim/ root: Rscript R/analysis/diagnose_convergence.R

source("R/core/_setup.R")

scenario <- "mk"
gridTag  <- "tl1.00_gl0.10_c100"
repID    <- "sim001"
models   <- c("model1", "model2", "model3", "model4")

cat("=== Tree counts per model (run 1) ===\n")
for (m in models) {
  trees <- tryCatch(.LoadTrees(scenario, gridTag, repID, m, 1),
                     error = function(e) NULL)
  n <- if (is.null(trees)) NA_integer_ else length(trees)
  ntaxa <- if (is.null(trees)) NA_integer_ else length(trees[[1]]$tip.label)
  cat(sprintf("%-8s trees=%-6s taxa=%-4s\n", m, n, ntaxa))
}

cat("\n=== Per-stage timing per model ===\n")
for (m in models) {
  cat(sprintf("\n--- %s ---\n", m))

  t0 <- Sys.time()
  treesList <- lapply(1:2, function(run) .LoadTrees(scenario, gridTag, repID, m, run))
  cat(sprintf("  LoadTrees (both runs): %.2fs\n", as.numeric(Sys.time() - t0, units = "secs")))

  t0 <- Sys.time()
  asdsf <- tryCatch(ComputeASDSF(scenario, gridTag, repID, m, treesList = treesList),
                     error = function(e) NA_real_)
  cat(sprintf("  ASDSF:                 %.2fs\n", as.numeric(Sys.time() - t0, units = "secs")))

  t0 <- Sys.time()
  tree_ess <- tryCatch(ComputeTreeESS(scenario, gridTag, repID, m, treesList = treesList),
                        error = function(e) NA_real_)
  cat(sprintf("  TreeESS:                %.2fs\n", as.numeric(Sys.time() - t0, units = "secs")))

  cat(sprintf("  asdsf=%.5f tree_ess=%.1f\n", asdsf, tree_ess))
}
