# converts rows of param_grid into positional argument vectors for revbayes scripts via rb --args on hamilton
# row     <- PARAM_GRID[i, ]
# simDir  <- SimDirAbs("nt", GridTag(row), SimID(rep))
# rb_args <- NtSimArgs(row, simDir, seed = rep)

NtSimArgs <- function(row, simDir, seed) {
  c(
    simDir,
    as.character(row$n_taxa),
    as.character(row$n_neo),
    as.character(row$n_trans),
    as.character(row$gain_loss),    # arg[5]: gain-to-loss ratio
    as.character(row$part_rate),    # arg[6]: transformational partition rate
    as.character(row$tree_length),
    as.character(seed)
  )
}

#rb args for mk generative simulation, matches sim-by_mk_kv.rev. gain_loss and part_rate are passed for interface compatibility with
#NtSimArgs but are ignored by sim-by_mk_kv.rev
MkSimArgs <- function(row, simDir, seed) {
  c(
    simDir,
    as.character(row$n_taxa),
    as.character(row$n_neo),
    as.character(row$n_trans),
    as.character(row$gain_loss),    #ignored  mk
    as.character(row$part_rate),    # same
    as.character(row$tree_length),
    as.character(seed)
  )
}

#rb args for inference, matches sim-mc3.rev:
InferArgs <- function(simDir, outDir, scriptID, minEss = 333L, seed = 0L) {
  c(
    simDir,
    outDir,
    scriptID,
    as.character(minEss),
    as.character(seed)
  )
}

# picks the simulation argument builder for a given scenario
SimArgsFn <- function(scenario) {
  switch(scenario,
    nt = NtSimArgs,
    mk = MkSimArgs,
    stop("Unknown scenario: ", scenario, ". Use 'nt' or 'mk'.")
  )
}
