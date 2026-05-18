# Checks MCMC convergence for every completed inference run across all simulations × 12 models, flags failures, and writes a re-queue list.

# Workflow:
# - Source R/_setup.R to load options and packages.
# - Enumerate all completed RevBayes .log and .trees file pairs in nt-sim-data/logs/.
# - Call Convergence.R::CheckConvergence() for each run (ESS >= 200, rank-normalised R-hat < 1.01, ASDSF < 0.01).
# - Save a convergence summary .rds (pass/fail per run with diagnostic values).
# - Print a list of non-converged runs for re-submission with submit_inference.R.

