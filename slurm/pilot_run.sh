#!/bin/bash
# pilot_run.sh
# Pilot SLURM job: simulate data under NT model and run Model 1 inference.
# Adapted from mc3sim.sh (supervisor).
# Runs a single replicate (sim001) with reduced resources for a quick pipeline test.
# Outputs are written to the-matrix repo and pushed to GitHub.
 
# --- Resource requests ---
#SBATCH -n 4                          # 4 tasks (4 MPI chains for pilot)
#SBATCH --mem=4G                      # modest memory for small dataset
#SBATCH --time=3:00:00                # 3-hour cap (sim + 2-hr inference)
#SBATCH --job-name=pilot_model1
#SBATCH --output=/nobackup/%u/morphosim/pilot_model1.out
#SBATCH --error=/nobackup/%u/morphosim/pilot_model1.err
#SBATCH -p shared
#SBATCH --export=ALL
# --- Load modules before anything else ---
module load gcc/11.2
module load boost/1.78.0
module load openmpi/4.1.1
 
RB=~/diss/revbayes/projects/cmake/build-mpi/rb-mpi
WORK=/nobackup/$USER/morphosim
MATRIX=/nobackup/$USER/the-matrix
SIM_SUBDIR=simulations/pilot/sim001
 
# Clone/pull morphosim (code)
if [ -d "$WORK/.git" ]; then
  cd $WORK && git pull origin main --rebase
else
  git clone --depth 1 https://${MORPHOSIM_TOKEN}@github.com/Kaishyad/morphosim.git $WORK
fi
 
# Clone/pull the-matrix (data)
if [ -d "$MATRIX/.git" ]; then
  cd $MATRIX && git pull origin main --rebase
else
  git clone --depth 1 https://${MATRIX_TOKEN}@github.com/Kaishyad/the-matrix.git $MATRIX
fi
 
# Create output directory inside the-matrix
mkdir -p $MATRIX/$SIM_SUBDIR
 
# --- Step 1: Simulate data ---
echo "Starting simulation at $(date)"
$RB $WORK/rbScripts/pilot_sim.Rev \
  $MATRIX/$SIM_SUBDIR 20 30 30 0.497 2.47 1.43 1
echo "Simulation complete at $(date)"
 
# --- Step 2: Run Model 1 inference ---
echo "Starting inference at $(date)"
mpirun $RB \
  $WORK/rbScripts/pilot_infer.Rev \
  $MATRIX/$SIM_SUBDIR model1 200
echo "Inference complete at $(date)"
 
# --- Step 3: Compress tree files ---
cd $MATRIX/$SIM_SUBDIR
for file in *.trees; do
  [ -f "$file" ] && tar -czf "${file%.trees}.tar.gz" "$file" && rm "$file"
done
 
# --- Step 4: Push outputs to the-matrix ---
cd $MATRIX
git add $SIM_SUBDIR/
git commit -m "Pilot run: sim001 model1 output"
git pull origin main --rebase
git push origin main
 
echo "All done at $(date)"