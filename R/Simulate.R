# Simulate.R
#
# Provides wrapper functions for generating simulated datasets across the full
# parameter grid under both NT and Mk generative models.
#
# Key functions to implement:
#   BuildNTArgs()   - Constructs argument lists for the NT generative RevBayes
#                     script (sim-by_nt_kv.Rev), given tree_length, rate_ratio,
#                     and n_char from the parameter grid.
#   BuildMkArgs()   - As above but for the symmetric Mk generative model
#                     (sim-by_mk_kv.Rev); used for the contrast scenario that
#                     tests whether NT inference is harmful when Mk is true.
#   SplitCharacters() - Splits a combined character matrix into neomorphic
#                       (neo.nex) and transformational (trans.nex) partitions
#                       following NT model conventions.
#   SaveSimMeta()   - Writes simulation metadata (seed, parameters, file paths)
#                     to a .rds file alongside each simulation output directory.
#
# Wraps and extends the supervisor's simFuncs.R (QueueSim, SimTrees,
# PackageFile) with grid-loop logic.
#
# Used in: analysis/01_simulate.R
# Dissertation section: 5.1 Basic / 5.2 Intermediate (Data generation)
