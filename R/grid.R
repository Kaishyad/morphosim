# Defines the full parameter grid 
#   Tree length:           0.5, 1.0, 2.0, 4.0
#   Gain-to-loss ratio:    0.5, 1.0, 2.5, 5.0
#   Character count:        50, 100, 200, 400
#   Taxon number:           30  (fixed)


# main object to define:
#   PARAM_GRID- a data.frame of all 64 parameter combinations iterated
#                 over by simulate.R and submit_inference.R.


PARAM_GRID <- expand.grid(
  tree_length = c(0.5, 1.0, 2.0, 4.0),
  gain_loss   = c(0.5, 1.0, 2.5, 5.0),
  n_char      = c(50L, 100L, 200L, 400L),
  n_taxa      = 30L,
  KEEP.OUT.ATTRS   = FALSE,
  stringsAsFactors = FALSE
)

