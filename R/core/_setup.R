# Source this at the top of every analysis script: source("R/core/_setup.R")

# --- Paths ---
options("ntOutDir"      = file.path(dirname(getwd()), "the-matrix"))
options("ntRepoDir"     = file.path(getOption("ntOutDir"), "simulations"))
options("ntSlurmDir"    = file.path(getwd(), "slurm"))
options("ntRBScriptDir" = file.path(getwd(), "rbScripts"))
options("ntRemoteDir"   = paste0("/nobackup/", Sys.getenv("USER")))

# --- Packages ---
library(ape)
library(TreeTools)
library(TreeDist)
library(mgcv)
library(ggplot2)
library(cli)

# Source core files first so FilePaths.R, Grid.R etc are defined
# before anything that depends on them.
for (f in list.files("R/core", pattern = "\\.R$", full.names = TRUE)) {
  if (grepl("_setup\\.R", f)) next
  source(f)
}

# Source function libraries only — not analysis/validation scripts
# which are meant to be run standalone after inference.
for (d in c("R/model", "R/simulation", "R/outputs")) {
  for (f in list.files(d, pattern = "\\.R$", full.names = TRUE)) {
    source(f)
  }
}

# --- Reproducibility ---
set.seed(636)

# --- Constants ---
N_TIP     <- 50L
N_REP     <- 100L
MODEL_IDS <- paste0("model", 1:12)

# Convergence thresholds from Vehtari et al. 2021
ESS_MIN   <- 333   # minimum ESS per parameter
RHAT_MAX  <- 1.01  # rank-normalised R-hat ceiling
ASDSF_MAX <- 0.01  # average SD of split frequencies ceiling