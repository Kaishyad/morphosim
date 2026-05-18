# Convergence.R
# Implements MCMC convergence diagnostics for all inference runs
# Used in: analysis/check_convergence.R

# Key functions to implement:
#   ComputeRhat()  - Rank-normalised split R-hat per Vehtari et al. (2021). Applied to all continuous parameters in RevBayes .log files.
#   ComputeESS() - Effective Sample Size calculation for each continuous parameter; flags parameters below the 200-sample threshold.
#   ComputeASDSF() - Average Standard Deviation of Split Frequencies for tree topology convergence; reads paired .trees files.
#   CheckConvergence() - Combines the three criteria into a single boolean pass/fail with a named summary list for reporting and re-queuing logic.

# Parallels the martin's CheckComplete.R (ESS, PSRF, HasConverged) but uses rank-normalised R-hat 


