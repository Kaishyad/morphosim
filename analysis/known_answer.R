# Checks that 95% posterior credible intervals contain the true simulated value in ~95% of replicates.

# Workflow:
#   - Source R/_setup.R.
#   - Load the list of converged runs from check_convergence.R output.
#   - For each replicate: load .log file, extract CI for tree_length and
#      gain-to-loss ratio via KnownAnswer.R::CredibleInterval(), compare to
#      known true values stored in simulation metadata .rds files.
#   - Compute coverage rates per grid cell via KnownAnswer.R::CoverageRate().
#   - Summarise and export via KnownAnswer.R::KnownAnswerSummary().
