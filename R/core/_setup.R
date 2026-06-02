#Source this at the top of every analysis script = source("R/core/_setup.R")

# ---Paths ---
# Local clone of the-matrix data repository
options("ntOutDir"      = file.path(dirname(getwd()), "the-matrix"))
options("ntRepoDir"     = file.path(getOption("ntOutDir"), "simulations"))
options("ntSlurmDir"    = file.path(getwd(), "slurm"))
options("ntRBScriptDir" = file.path(getwd(), "rbScripts"))
options("ntRemoteDir"   = paste0("/nobackup/", Sys.getenv("USER")))

#--- Packages ---
library(ape)
library(TreeTools)
library(TreeDist)
library(mgcv)      
library(ggplot2)
library(cli)

for (f in list.files("R", pattern = "^(?!_setup).*\\.R$",
                     full.names = TRUE, perl = TRUE)) {
  source(f)
}

# --- Reproducibility <3
set.seed(636) 

# --- Constants ---
N_TIP <- 30L    
N_REP <- 100L   
MODEL_IDS <- paste0("model", 1:12)

# Convergence thresholds from Vehtari et al. 2021
ESS_MIN   <- 333  # minimum ESS per parameter 
RHAT_MAX  <- 1.01  # rank-normalised R-hat ceiling
ASDSF_MAX <- 0.01 # average SD of split frequencies ceiling