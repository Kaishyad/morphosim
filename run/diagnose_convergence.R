#Diagnostic: compare tree counts and per-stage timing across models

source("R/core/_setup.R")
scenario <- "nt"
gridTag  <- "tl1.00_gl0.10_c100_pr0.25"   # real nt gridTag
models   <- paste0("model", 1:12)

for (m in models) {
  trees <- tryCatch(.LoadTrees(scenario, gridTag, "sim001", m, 1), error = function(e) NULL)
  cat(sprintf("%-8s trees=%s\n", m, if(is.null(trees)) "NA" else length(trees)))
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
