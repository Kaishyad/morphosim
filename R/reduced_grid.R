# Defines the minimum viable analysis grid as a fallback
# The reduced grid retains the extremes and midpoint of each parameter axis:
#   Tree length:         0.5, 1.0, 4.0    
#   Gain-to-loss ratio:  0.5, 2.5, 5.0      
#   Character count:     50,  200, 400      


#main object to define:
#   REDUCED_GRID - a data.frame or list of parameter combinations used in
#                   place of the full grid wherever lapply() iterates.


# CheckComplete.R can be used to identify which full-grid cells are done and
# whether the reduced grid is already covered as a subset.

REDUCED_GRID <- expand.grid(
  tree_length = c(0.5, 2.0, 4.0),
  gain_loss   = c(0.5, 2.5, 5.0),
  n_char      = c(50L, 200L, 400L),
  n_taxa      = 30L,
  KEEP.OUT.ATTRS   = FALSE,
  stringsAsFactors = FALSE
)