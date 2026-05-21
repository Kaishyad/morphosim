# ThresholdGAM.R
# NEW file for nt-sim project.
#
# Fits Generalised Additive Models (GAMs) to identify parameter thresholds at
# which NT models outperform the Mk baseline in topological accuracy.
#
# Key functions to implement:
#   ComputeImprovement()  - Calculates per-replicate NT improvement over Mk
#                           baseline: delta_CID = CID_Mk - CID_NT (positive =
#                           NT better).
#   FitThresholdGAM()     - Fits mgcv::gam(improvement ~ s(tree_length) +
#                           s(rate_ratio) + s(chars_per_taxon)) for one inference
#                           model; checks basis dimension with gam.check().
#   ExtractThreshold()    - Identifies the parameter value at which the GAM
#                           smooth crosses zero (NT starts to outperform Mk)
#                           using uniroot() on the predicted smooth.
#   SensitivityCheck()    - Re-fits GAM with doubled basis dimension k; flags
#                           models where threshold estimate shifts substantially.
#   ThresholdSummary()    - Applies FitThresholdGAM + ExtractThreshold across
#                           all 12 inference models; returns tidy data frame.
#
# Uses Wood (2017) mgcv package. One GAM per inference model per parameter axis.
#
# Used in: analysis/09_threshold_gam.R
# Dissertation section: 5.3 Threshold detection
