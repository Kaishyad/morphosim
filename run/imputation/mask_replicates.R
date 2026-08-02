# Masks a proportion of observed character states across every replicate in
# the grid, writing imp_neo.nex / imp_trans.nex next to each replicate's
# neo.nex / trans.nex. Run this BEFORE slurm/Infer.R --imputation.
#
# Usage:
#   Rscript run/imputation/mask_replicates.R                     # dry run, all
#   Rscript run/imputation/mask_replicates.R --run                # do it
#   Rscript run/imputation/mask_replicates.R --run --scenario mk  # mk only
#   Rscript run/imputation/mask_replicates.R --run --prop 0.15    # mask 15% instead of the 10% default

source("R/core/_setup.R")

args_cli      <- commandArgs(trailingOnly = TRUE)
dry_run       <- !("--run" %in% args_cli)
scenario_flag <- args_cli[which(args_cli == "--scenario") + 1]
prop_flag     <- args_cli[which(args_cli == "--prop")     + 1]

scenarios <- if (!is.na(scenario_flag[1])) scenario_flag else c("nt", "mk")
propMask  <- if (!is.na(prop_flag[1])) as.numeric(prop_flag) else 0.1

if (dry_run) message("Dry run — pass --run to actually write imp_*.nex files")
message(sprintf("Scenarios: %s | propMask: %.2f", paste(scenarios, collapse = ", "), propMask))

masked  <- 0L
skipped <- 0L

for (scenario in scenarios) {
  grid <- if (scenario == "mk") {
    unique(PARAM_GRID[, c("tree_length", "gain_loss", "n_char",
                          "n_taxa", "n_neo", "n_trans")])
  } else {
    PARAM_GRID
  }

  for (gi in seq_len(nrow(grid))) {
    row     <- grid[gi, ]
    gridTag <- GridTag(row)

    for (rep in seq_len(N_REP)) {
      repID     <- SimID(rep)
      simDirAbs <- SimDirAbs(scenario, gridTag, repID)

      if (!file.exists(file.path(simDirAbs, "neo.nex"))) {
        skipped <- skipped + 1L
        next
      }

      # Skip replicates that are already masked (re-run with --run again
      # after a partial failure without re-masking everything from scratch)
      if (file.exists(file.path(simDirAbs, "imp_neo.nex")) &&
         file.exists(file.path(simDirAbs, "imp_trans.nex"))) {
        skipped <- skipped + 1L
        next
      }

      if (dry_run) {
        message(sprintf("[DRY RUN] would mask %s | %s | %s", scenario, gridTag, repID))
        next
      }

      # seed = deterministic per replicate so re-running is reproducible
      res <- MaskReplicate(scenario, gridTag, repID, propMask = propMask,
                           seed = rep)
      message(sprintf("Masked %s | %s | %s -- neo: %d cells, trans: %d cells",
                      scenario, gridTag, repID, res$neo, res$trans))
      masked <- masked + 1L
    }
  }
}

message(sprintf("\nMasked: %d  |  Skipped (no sim data / already masked): %d",
                masked, skipped))
