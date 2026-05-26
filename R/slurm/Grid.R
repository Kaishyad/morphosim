#Defines the full and reduced parameter grids 
#simulation variables are derived here and passed to Rev scripts
# simArgs is interface logic
# Grid axes:
#   tree_length : total tree length (expected substitutions per site)
#   gain_loss   : gain-to-loss rate ratio for neomorphic characters
#   n_char      : total character count (split into neo + trans by NEO_FRAC)
#   n_taxa      : fixed taxon count (constant across all cells)

# Derived columns added automatically:
#   n_neo       : neomorphic character count  = round(n_char * NEO_FRAC)
#   n_trans     : transformational char count = n_char - n_neo
#   part_rate   : transformational partition rate scalar 

.NEO_FRAC   <- 0.40    # proportion of characters that are neomorphic
.PART_RATE  <- 2.47    # transformational partition rate scalar (t in sim scripts)


PARAM_GRID <- local({
  g <- expand.grid(
    tree_length = c(0.5, 1.0, 2.0, 4.0),
    gain_loss   = c(0.5, 1.0, 2.5, 5.0),
    n_char      = c(50L, 100L, 200L, 400L),
    n_taxa      = 30L,                       
    KEEP.OUT.ATTRS   = FALSE,
    stringsAsFactors = FALSE
  )
  # Derive character split from n_char
  g$n_neo   <- as.integer(round(g$n_char * .NEO_FRAC))
  g$n_trans <- g$n_char - g$n_neo
  # Partition rate scalar: fixed for now, can be promoted to a grid axis
  g$part_rate <- .PART_RATE
  g
})

# --- Reduced grid (minimum viable analysis fallback
# CheckComplete.R::CheckIncomplete() reports which cells still need running.

REDUCED_GRID <- local({
  g <- expand.grid(
    tree_length = c(0.5, 2.0, 4.0),
    gain_loss   = c(0.5, 2.5, 5.0),
    n_char      = c(50L, 200L, 400L),
    n_taxa      = 20L,
    KEEP.OUT.ATTRS   = FALSE,
    stringsAsFactors = FALSE
  )
  g$n_neo     <- as.integer(round(g$n_char * .NEO_FRAC))
  g$n_trans   <- g$n_char - g$n_neo
  g$part_rate <- .PART_RATE
  g
})

