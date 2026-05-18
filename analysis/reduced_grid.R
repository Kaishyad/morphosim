# Defines the minimum viable analysis grid as a fallback if the full parameter
# grid cannot be completed within the dissertation timeline.

# The reduced grid retains the extremes and midpoint of each parameter axis:
#   Tree length:         0.5, 1.0, 4.0    
#   Gain-to-loss ratio:  0.5, 2.5, 5.0      
#   Character count:     50,  200, 400      


# Key object to define:
#   REDUCED_GRID  - a data.frame or list of parameter combinations used in
#                   place of the full grid wherever lapply() iterates.


# CheckComplete.R can be used to identify which full-grid cells are done and
# whether the reduced grid is already covered as a subset.

