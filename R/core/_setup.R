# paths
options("ntOutDir"      = file.path(dirname(getwd()), "the-matrix"))
options("ntRepoDir"     = file.path(getOption("ntOutDir"), "simulations"))
options("ntSlurmDir"    = file.path(getwd(), "slurm"))
options("ntRBScriptDir" = file.path(getwd(), "rbScripts"))
options("ntRemoteDir"   = paste0("/nobackup/", Sys.getenv("USER")))
options("ntTmpDir"      = file.path(getOption("ntRemoteDir"), "tmp"))
options("ntRbBinary"    = file.path(Sys.getenv("HOME"), "diss/revbayes/projects/cmake/build-mpi/rb-mpi"))

library(ape)
library(TreeTools)
library(TreeDist)
library(mgcv)
library(ggplot2)
library(cli)

# source core files
for (f in list.files("R/core", pattern = "\\.R$", full.names = TRUE)) {
  if (grepl("_setup\\.R", f)) next
  source(f)
}

# source function libraries
for (d in c("R/model", "R/simulation", "R/outputs")) {
  for (f in list.files(d, pattern = "\\.R$", full.names = TRUE)) {
    source(f)
  }
}
source("R/analysis/Convergence.R")
source("R/analysis/TreeAnalysis.R")
source("R/analysis/ThresholdGAM.R")

# constants
set.seed(636)
N_TIP <- 50L
N_REP <- 10L
MODEL_IDS <- paste0("model", 1:12)

# convergence thresholds
ESS_MIN   <- 256   #minimum ess per parameter
RHAT_MAX  <- 1.02  #rank-normalised r-hat ceiling
ASDSF_MAX <- 0.05  #average sd of split frequencies ceiling

.config <- list(
  grid          = PARAM_GRID,
  nRep          = N_REP,
  psrfThreshold = RHAT_MAX,
  essThreshold  = ESS_MIN
)
