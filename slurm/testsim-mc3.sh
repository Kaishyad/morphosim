#!/bin/bash
#SBATCH -n 4
#SBATCH --mem=8G
#SBATCH --time=1:00:00
#SBATCH --job-name=testsim-mc3-test
#SBATCH --output=/nobackup/%u/morphosim/logs/testsim-mc3-test.out
#SBATCH --error=/nobackup/%u/morphosim/logs/testsim-mc3-test.err
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
cd $MORPHOSIM && git pull origin models --rebase

mkdir -p $MORPHOSIM/logs

# ── NT x model1 ───────────────────────────────────────────────────────────────
echo "NT model1 starting at $(date)"
$RB $MORPHOSIM/rbScripts/Sims/sim-mc3-test.Rev \
  $NT_DIR model1 $MIN_ESS $SEED
echo "NT model1 done at $(date)"

cd $MATRIX
git add simulations/testsim/nt/
git commit -m "Testsim: mc3-test model1 NT results" || true
git pull origin main --rebase
git push origin main

# ── Mk x model1 ───────────────────────────────────────────────────────────────
echo "Mk model1 starting at $(date)"
$RB $MORPHOSIM/rbScripts/Sims/sim-mc3-test.Rev \
  $MK_DIR model1 $MIN_ESS $SEED
echo "Mk model1 done at $(date)"

cd $MATRIX
git add simulations/testsim/mk/
git commit -m "Testsim: mc3-test model1 Mk results" || true
git pull origin main --rebase
git push origin main

echo "All done at $(date)"