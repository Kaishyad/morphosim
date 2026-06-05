#The full parameter grid
#Simulation variables are saved here and passed to Rev scripts

.NEO_FRAC  <- 0.40   
.PART_RATE <- 2.47   

PARAM_GRID <- local({
  g <- expand.grid(
    tree_length = c(1.0, 1.5, 2.5, 3),  
    gain_loss   = c(0.25, 0.5, 1.0, 2.0), 
    n_char      = c(25L, 50L, 75L, 100L),
    n_taxa      = 50L,                     
    KEEP.OUT.ATTRS   = FALSE,
    stringsAsFactors = FALSE
  )
  g$n_neo   <- as.integer(round(g$n_char * .NEO_FRAC))
  g$n_trans <- g$n_char - g$n_neo
  g$part_rate <- .PART_RATE
  g
})
