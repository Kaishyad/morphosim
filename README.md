# Morphosim
Simulation study comparing Mk and NT models for Bayesian morphological phylogenetic inference.



## Project overview

This repository contains all R scripts, RevBayes (`.Rev`) inference scripts, and SLURM
batch scripts needed to:

1. Simulate morphological character matrices under the NT generative model across a parameter grid.
2. Run Bayesian inference under twelve models via RevBayes on the Hamilton HPC cluster.
3. Assess tree accuracy, missing-data imputation accuracy, MCMC convergence, and posterior predictive adequacy.

Simulation outputs (MCMC logs, tree files, result `.rds` files) are stored in the companion
data repository: **the-matrix**.

## Parameter grid

| Parameter              | Values                    |
|------------------------|---------------------------|
| Tree length            | 0.5, 1.0, 2.0, 4.0       |
| Gain-to-loss ratio (t) | 0.5, 1.0, 2.5, 5.0       |
| Character count        | 50, 100, 200, 400         |
| Taxon number           | 28 (fixed)                |
| Replicates per cell    | TBD (≥10 target)          |

## Models

| Group | Models | Description                                        |
|-------|--------|----------------------------------------------------|
| 1     | 1–3    | Single-partition, no rate heterogeneity            |
| 2     | 4–6    | Two-partition (NT), no rate heterogeneity          |
| 3     | 7–10   | Two-partition (NT), with rate variation            |
| 4     | 11–12  | Novel extensions                                   |
