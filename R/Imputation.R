# Imputation.R
# NEW file for nt-sim project.
#
# Missing-data imputation accuracy: masks a fraction of characters before
# inference, then scores ancestral state reconstruction against the known
# true states.
#
# Key functions to implement:
#   MaskCharacters()         - Randomly masks a proportion of characters in the
#                              nexus matrix (rate drawn from the empirical missing-
#                              data distribution via .Ambiguate from simFuncsImp.R),
#                              writing imp_neo.nex and imp_trans.nex.
#   ScoreImputation()        - Compares RevBayes ancestral state posteriors to
#                              known true states; returns per-character accuracy.
#   WilcoxonImputation()     - Pairwise Wilcoxon signed-rank test comparing
#                              imputation accuracy distributions between each model
#                              and the Mk baseline (Model 1), across the full grid.
#   ImputationForReplicate() - Top-level wrapper for one replicate: mask ->
#                              score -> return accuracy; designed for lapply().
#
# Wraps the supervisor's simFuncsImp.R (.PoolRuns, .MeanAcc, .Ambiguate).
#
# Used in: analysis/06_imputation.R
# Dissertation section: 6.3 Imputation accuracy
