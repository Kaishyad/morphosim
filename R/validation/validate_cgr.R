# validate_cgr.R
# NEW file for nt-sim project.
#
# Standalone Cook-Gelman-Rubin coverage validation script.
# Loops over all converged replicates, extracts 95% posterior credible intervals
# for the two focal parameters (tree_length and gain-to-loss ratio), and checks
# whether each interval contains the known true simulated value.
#
# Workflow:
#   1. Load all converged .log files identified by analysis/03_check_convergence.R.
#   2. For each replicate: extract CI via KnownAnswer.R::CredibleInterval().
#   3. Compute coverage rate per grid cell via KnownAnswer.R::CoverageRate().
#   4. Summarise across the full grid and export results for dissertation Section 6.1.
#
# Expected output: a .rds file of coverage rates per (parameter, model, grid cell)
# and a CSV for Table 6.1.
#
# Used in: (called from analysis/04_known_answer.R)
# Dissertation section: 6.1 Correctness
