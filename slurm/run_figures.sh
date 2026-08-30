#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --mem=4G
#SBATCH --time=00:10:00
#SBATCH -p shared
#SBATCH --job-name=figures
#SBATCH --output=logs/figures_%j.out
#SBATCH --error=logs/figures_%j.err

# Under sbatch, SLURM copies this script into a job-specific spool directory
# before executing it, so ${BASH_SOURCE[0]} no longer points at its real
# location in the repo -- config.sh would silently fail to source (MATRIX_DIR/
# MORPHOSIM_DIR/BRANCH stay unset) and any $MATRIX_DIR-based cd/git command
# later in this script would then operate on the wrong directory. SLURM sets
# SLURM_SUBMIT_DIR to the directory `sbatch` was run from, which is what we
# actually want. Fall back to BASH_SOURCE-based resolution for the case where
# this script is run directly (not via sbatch).
if [ -n "$SLURM_SUBMIT_DIR" ]; then
  SCRIPT_DIR="$SLURM_SUBMIT_DIR/slurm"
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
source "$SCRIPT_DIR/config.sh"
module load r

cd "$MORPHOSIM_DIR"

echo "=== $(date '+%Y-%m-%d %H:%M:%S') starting results_figures_extra ==="
Rscript run/misc/results_figures_extra.R
echo "=== $(date '+%Y-%m-%d %H:%M:%S') finished results_figures_extra ==="
