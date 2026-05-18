# Generate and (optionally) submit SLURM jobs for all model × simulation combinations.
#
# Usage:
#   Rscript analysis/submit_inference.R              # write SLURM scripts only
#   Rscript analysis/submit_inference.R --submit     # also run sbatch

source("R/_setup.R")

submit <- "--submit" %in% commandArgs(trailingOnly = TRUE)

seeds     <- seq_len(N_REP)
model_ids <- MODEL_IDS

for (seed in seeds) {
  simID <- SimID(seed)
  for (modelID in model_ids) {

    result_file <- ResultFile(simID, modelID)
    if (file.exists(result_file)) {
      message(sprintf("Skipping %s × %s (result exists)", simID, modelID))
      next
    }

    slurm_path <- SlurmFile(simID, modelID)
    # MakeSlurm(simID, modelID, slurmPath = slurm_path)   # uncomment when implemented

    if (submit) {
      system(paste("sbatch", shQuote(slurm_path)))
      message(sprintf("Submitted: %s × %s", simID, modelID))
    } else {
      message(sprintf("SLURM script written: %s", slurm_path))
    }
  }
}
