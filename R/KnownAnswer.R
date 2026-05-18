# Cook-Gelman-Rubin simulation-based calibration check (Talts et al. 2018).
# Verifies that 95% posterior credible intervals contain the true simulated
# parameter value in approximately 95% of replicates 

# Key functions to implement:
#   CredibleInterval()   - Extracts the 2.5th and 97.5th posterior quantiles for
#                          a named parameter from a RevBayes .log file.
#   CoversTrue()         - Returns TRUE if the credible interval contains the
#                          known true value used to generate that simulation.
#   CoverageRate()       - Loops over replicates within a grid cell and computes
#                          the empirical coverage proportion.
#   KnownAnswerSummary() - Produces a summary data frame across all grid cells
#                          and both focal parameters (tree_length, gain-to-loss
#                          ratio)

# Used in: analysis/known_answer.R
