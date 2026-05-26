#!/bin/bash
#SBATCH -n 4
#SBATCH --mem=4G
#SBATCH --time=3:00:00
#SBATCH --job-name=testsim
#SBATCH --output=/nobackup/%u/morphosim/logs/testsim.out
#SBATCH --error=/nobackup/%u/morphosim/logs/testsim.err
#SBATCH -p shared
#SBATCH --export=ALL

module load gcc/11.2
module load boost/1.78.0
module load openmpi/4.1.1

RB=~/diss/revbayes/projects/cmake/build-mpi/rb-mpi
MORPHOSIM=/nobackup/$USER/morphosim
MATRIX=/nobackup/$USER/the-matrix

# --- Reduced grid midpoint row (R/Grid.R: REDUCED_GRID row 14) ---
# tree_length=2.0, gain_loss=2.5, n_char=200, n_taxa=20
# n_neo  = round(200 * 0.40) = 80
# n_trans = 200 - 80         = 120
# part_rate = 2.47 (supervisor empirical median, fixed in Grid.R)
GRID_TREE_LEN=2.00
GRID_GAIN_LOSS=2.50
GRID_N_TAXA=30
GRID_N_NEO=80
GRID_N_TRANS=120
GRID_PART_RATE=2.47
GRID_TAG="tl2.00_gl2.50_c200"
SEED=1

# --- Pull latest code and data ---
cd $MORPHOSIM && git pull origin main --rebase
cd $MATRIX    && git pull origin main --rebase

mkdir -p $MORPHOSIM/logs

# ── NT simulation ──────────────────────────────────────────────────────────────
NT_DIR=$MATRIX/simulations/testsim/nt/${GRID_TAG}/sim001
mkdir -p $NT_DIR

echo "NT simulation starting at $(date)"
$RB $MORPHOSIM/rbScripts/Sims/sim-by_nt_kv.Rev \
  --args $NT_DIR $N_TAXA $N_NEO $N_TRANS $GAIN_LOSS $PART_RATE $TREE_LEN $SEED
echo "NT simulation done at $(date)"

for f in neo.nex trans.nex tree.nwk; do
  if [ -f "$NT_DIR/$f" ]; then echo "  OK: $f"
  else echo "  MISSING: $f"; fi
done

# ── Mk simulation ──────────────────────────────────────────────────────────────
MK_DIR=$MATRIX/simulations/testsim/mk/${GRID_TAG}/sim001
mkdir -p $MK_DIR

echo "Mk simulation starting at $(date)"
$RB $MORPHOSIM/rbScripts/Sims/sim-by_mk_kv.Rev \
  --args $MK_DIR $N_TAXA $N_NEO $N_TRANS $GAIN_LOSS $PART_RATE $TREE_LEN $SEED
echo "Mk simulation done at $(date)"

for f in neo.nex trans.nex tree.nwk; do
  if [ -f "$MK_DIR/$f" ]; then echo "  OK: $f"
  else echo "  MISSING: $f"; fi
done

# ── Push to the-matrix ────────────────────────────────────────────────────────
cd $MATRIX
git add simulations/testsim/
git commit -m "Testsim: nt and mk sim001 simulated data only" || true
git pull origin main --rebase
git push origin main

echo "All done at $(date)"