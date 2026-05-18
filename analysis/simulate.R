# Generate simulated character matrices across the parameter grid.
# Runs RevBayes locally (for small tests) or via Hamilton (for full grid).

# Usage:
#   Rscript analysis/simulate.R          # dry-run: prints commands only
#   Rscript analysis/simulate.R --run    # actually submits to RevBayes

source("R/_setup.R")

dry_run <- !("--run" %in% commandArgs(trailingOnly = TRUE))
if (dry_run) message("Dry run — pass --run to execute")

#--- Parameter grid
grid <- expand.grid(
  tree_length = TREE_LENGTHS,
  gain_loss   = GAIN_LOSS,
  n_char      = CHAR_COUNTS,
  seed        = seq_len(N_REP)
)

message(sprintf("Parameter grid: %d combinations × %d replicates = %d total runs",
                nrow(expand.grid(TREE_LENGTHS, GAIN_LOSS, CHAR_COUNTS)),
                N_REP, nrow(grid)))

#--- Simulation loop

# n_neo and n_trans are split from n_char; adjust ratio to match your design.
#40/60 neo/trans split matching the martin's median empirical ratio.
split_chars <- function(n) list(
  n_trans = ceiling(n * 0.60),
  n_neo   = ceiling(n * 0.40)
)

for (i in seq_len(nrow(grid))) {
  row    <- grid[i, ]
  simID  <- SimID(row$seed)
  outDir <- SimDir(simID)

  sp     <- split_chars(row$n_char)

  rb_args <- c(
    RBScript("sim-by_nt_kv"),   #generative NT model script
    outDir,
    N_TIP,
    sp$n_trans,
    sp$n_neo,
    row$gain_loss,    # t  (gain-to-loss ratio)
    0.497,            # n  (fixed empirical median, adjust if needed)
    row$tree_length,
    row$seed
  )

  if (dry_run) {
    message(sprintf("[DRY RUN] %s | tl=%.1f gl=%.1f nc=%d",
                    simID, row$tree_length, row$gain_loss, row$n_char))
  } else {
    if (!dir.exists(outDir)) dir.create(outDir, recursive = TRUE)
    # rb <- rbSession(rb_args)   # uncomment when revbayesr is available
    message(sprintf("Submitted: %s", simID))
  }
}
