#!/bin/bash
#SBATCH -n 4
#SBATCH --mem=8G
#SBATCH --time=24:00:00
#SBATCH --job-name=testsim-mc3
#SBATCH --output=/nobackup/%u/morphosim/logs/testsim-mc3.out
#SBATCH --error=/nobackup/%u/morphosim/logs/testsim-mc3.err
#SBATCH -p shared
#SBATCH --export=ALL

module load gcc/11.2
module load boost/1.78.0
module load openmpi/4.1.1

RB=~/diss/revbayes/projects/cmake/build-mpi/rb-mpi
MORPHOSIM=/nobackup/$USER/morphosim
MATRIX=/nobackup/$USER/the-matrix

TAG="tl2.00_gl2.50_c200"
NT_DIR=$MATRIX/simulations/testsim/nt/${TAG}/sim001
MK_DIR=$MATRIX/simulations/testsim/mk/${TAG}/sim001

MIN_ESS=333
SEED=1

# --- Pull latest code ---
cd $MORPHOSIM && git pull origin main --rebase

mkdir -p $MORPHOSIM/logs

# ── NT x model1 ───────────────────────────────────────────────────────────────
echo "NT model1 starting at $(date)"
$RB $MORPHOSIM/rbScripts/Sims/sim-mc3.Rev \
  $NT_DIR model1 $MIN_ESS $SEED
echo "NT model1 done at $(date)"

# ── NT x model7 ───────────────────────────────────────────────────────────────
echo "NT model7 starting at $(date)"
$RB $MORPHOSIM/rbScripts/Sims/sim-mc3.Rev \
  $NT_DIR model7 $MIN_ESS $SEED
echo "NT model7 done at $(date)"

# ── Mk x model1 ───────────────────────────────────────────────────────────────
echo "Mk model1 starting at $(date)"
$RB $MORPHOSIM/rbScripts/Sims/sim-mc3.Rev \
  $MK_DIR model1 $MIN_ESS $SEED
echo "Mk model1 done at $(date)"

# ── Mk x model7 ───────────────────────────────────────────────────────────────
echo "Mk model7 starting at $(date)"
$RB $MORPHOSIM/rbScripts/Sims/sim-mc3.Rev \
  $MK_DIR model7 $MIN_ESS $SEED
echo "Mk model7 done at $(date)"

# ── Push results to the-matrix ────────────────────────────────────────────────
cd $MATRIX
git add simulations/testsim/
git commit -m "Testsim: mc3 inference model1 and model7 on nt and mk" || true
git pull origin main --rebase
git push origin main

echo "All done at $(date)"
