# Recount convergence pass/fail using RELAXED thresholds, entirely from the
# already-computed diagnostic columns in convergence_summary.rds. No reruns.
# New rule: rhat < 1.02 (unchanged), ess_min > 200 (was 256), tree_ess > 100
# (new, previously unused), asdsf < 0.05 (unchanged).

source("R/core/_setup.R")
source("run/shared/config_theme.R")

library(dplyr)

conv <- readRDS(PATHS$convergence)

RHAT_MAX   <- 1.02
ESS_MIN    <- 200     # relaxed from 256
TREE_ESS_MIN <- 100   # new criterion, previously computed but unused
ASDSF_MAX  <- 0.05

conv <- conv %>%
  mutate(
    rhat_pass_v2     = rhat_max <= RHAT_MAX,
    ess_pass_v2      = ess_min > ESS_MIN,
    tree_ess_pass_v2 = !is.na(tree_ess) & tree_ess > TREE_ESS_MIN,
    asdsf_pass_v2    = asdsf < ASDSF_MAX,
    pass_v2          = rhat_pass_v2 & ess_pass_v2 & tree_ess_pass_v2 & asdsf_pass_v2
  )

cat("Original pass rate: ", round(mean(conv$pass) * 100, 2), "%\n")
cat("Recomputed (relaxed ESS + tree_ess added) pass rate: ",
    round(mean(conv$pass_v2) * 100, 2), "%\n\n")

cat("By model x scenario:\n")
print(conv %>% group_by(scenario, modelID) %>%
        summarise(orig = round(mean(pass)*100,1),
                  v2   = round(mean(pass_v2)*100,1), .groups="drop"))

# Save the recount as a NEW file -- do not overwrite convergence_summary.rds,
# so the original (pipeline-generated) result remains the audit trail.
saveRDS(conv, file.path(PATHS$results_dir, "convergence_recount_relaxed.rds"))
write.csv(conv %>% filter(!pass_v2) %>% select(scenario, gridTag, repID, modelID),
          file.path(PATHS$results_dir, "requeue_list_v2.txt"), row.names = FALSE)
