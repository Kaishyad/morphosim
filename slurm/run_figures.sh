#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --mem=4G
#SBATCH --time=00:10:00
#SBATCH -p shared
#SBATCH --job-name=figures
#SBATCH --output=logs/figures_%j.out
#SBATCH --error=logs/figures_%j.err

# under sbatch, slurm copies this script into a job-specific spool directory
# before running it, so BASH_SOURCE no longer points at its real repo
# location and config.sh would fail to source. SLURM_SUBMIT_DIR is the
# directory sbatch was run from, which is what we want; fall back to
# BASH_SOURCE resolution when this script is run directly (not via sbatch).
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
