# Computes Clustering Information Distance (CID) between posterior trees and
# the known true tree for all converged runs under both generative scenarios.

# Workflow:
#   - Source R/_setup.R.
#   - Load converged run list from check_convergence.R.
#   - For each (simID, modelID): call TreeAccuracy.R::TreeAccuracyForReplicate()
#      which reads posterior trees, calls TreeDist::ClusteringInfoDist(), and
#      returns median and IQR.
#   - Combine NT-generated and Mk-generated scenarios side by side.
#   - Save combined result .rds to nt-sim-data/results/ for plotting.