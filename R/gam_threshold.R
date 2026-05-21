# gam_threshold.R
# NEW file for nt-sim project.
#
# Fits GAMs and extracts threshold estimates for each of the 12 inference models
# across all three parameter axes (tree length, gain-to-loss ratio,
# characters-per-taxon ratio).
#
# Workflow:
#   1. Load per-replicate CID improvement over Mk baseline.
#   2. Call ThresholdGAM.R::ThresholdSummary() for each inference model.
#   3. Run SensitivityCheck() to flag unstable threshold estimates.
#   4. Export summary data frame and GAM objects for plotting.
#
# Uses mgcv package (Wood 2017). One GAM per inference model.
#
# Dissertation section: 5.3 Threshold detection / GAM
