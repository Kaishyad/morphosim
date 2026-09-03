# full parameter grid simulation variables saved and passed to rev scripts

.NEO_FRAC <- 0.47

PARAM_GRID <- local({
  g <- expand.grid(
    tree_length = c(1.0, 1.5, 2.5, 5),
    gain_loss   = c(0.1, 0.25, 0.5, 1.0),
    part_rate   = c(1.0, 2.5, 5.0),
    n_char      = c(25L, 50L, 100L, 200L),
    n_taxa      = 50L,
    KEEP.OUT.ATTRS   = FALSE,
    stringsAsFactors = FALSE
  )
  g$n_neo   <- as.integer(round(g$n_char * .NEO_FRAC))
  g$n_trans <- g$n_char - g$n_neo
  g
})

BASELINE_BY_SCENARIO <- c(mk = "model1", nt = "model8")
