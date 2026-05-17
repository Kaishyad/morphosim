# R/_setup.R
# Global options for the nt-sim project.
# Source this at the top of every analysis script:
#   source("R/_setup.R")
#
# Edit the paths below to match your local environment before first use.
# Do NOT commit personal paths — keep them in a local .Rprofile if preferred.

# ── Paths ──────────────────────────────────────────────────────────────────────

# Local clone of the nt-sim-data repository
options("ntOutDir" = file.path(dirname(getwd()), "nt-sim-data"))

# Subdirectory within nt-sim-data where RevBayes repo folders are written
options("ntRepoDir" = file.path(getOption("ntOutDir"), "simulations"))

# SLURM script directory (within this repo)
options("ntSlurmDir" = file.path(getwd(), "slurm"))

# RevBayes .Rev script directory (within this repo)
options("ntRBScriptDir" = file.path(getwd(), "rbScripts"))

# Remote nobackup path on Hamilton (replace <username>)
options("ntRemoteDir" = paste0("/nobackup/", Sys.getenv("USER")))

# ── Packages ───────────────────────────────────────────────────────────────────

library(ape)
library(TreeTools)
library(TreeDist)
library(mgcv)      # GAM threshold analysis
library(ggplot2)
library(cli)

# Load project functions
for (f in list.files("R", pattern = "^(?!_setup).*\\.R$", full.names = TRUE, perl = TRUE)) {
  source(f)
}

# ── Reproducibility ────────────────────────────────────────────────────────────

# Default RNG seed for any local stochastic steps; individual simulations
# use their own seeds passed explicitly to RevBayes.
set.seed(42)

# ── Constants ──────────────────────────────────────────────────────────────────

N_TIP      <- 28L           # Taxon count (fixed throughout)
N_REP      <- 100L          # Target replicates per parameter cell

# Parameter grid axes
TREE_LENGTHS   <- c(0.5, 1.0, 2.0, 4.0)
GAIN_LOSS      <- c(0.5, 1.0, 2.5, 5.0)   # t (gain-to-loss ratio)
CHAR_COUNTS    <- c(50L, 100L, 200L, 400L)

# Model IDs (must match rbScripts filenames)
MODEL_IDS <- c(
  "sp_kv",          # Model 1  — single-partition, symmetric Mk baseline
  "sp_n_kv",        # Model 2
  "sp_nt_kv",       # Model 3
  "ns_ki",          # Model 4
  "ns_n_ki",        # Model 5
  "ns_nt_ki",       # Model 6
  "ns_t_ki",        # Model 7
  "sim_by_n_ki",    # Model 8
  "pInv_by_n_ki",   # Model 9  (pinv_by_n_ki.Rev)
  "pInv_hg_b_ki",   # Model 10
  "sp_kv_nonly",    # Model 11
  "sim-by_nt_kv"    # Model 12
)

# Convergence thresholds
ESS_MIN   <- 200
RHAT_MAX  <- 1.01
ASDSF_MAX <- 0.01
