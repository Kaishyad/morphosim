# Morphosim
Simulation dissertation comparing Mk and NT models for Bayesian morphological phylogenetic inference.


## Project overview

This repository contains all R scripts, RevBayes (`.Rev`) inference scripts, and SLURM
batch scripts needed to:

1. Simulate morphological character matrices under the NT generative model across a parameter grid.
2. Run Bayesian inference under twelve models via RevBayes on the HPC cluster.
3. Assess tree accuracy, MCMC convergence, and more diagnostics.

Simulation outputs (MCMC logs, tree files, result `.rds` files) are stored in the companion
data repository: **the-matrix** which can be found at https://github.com/Kaishyad/the-matrix.


