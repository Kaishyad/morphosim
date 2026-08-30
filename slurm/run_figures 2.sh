#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --mem=4G
#SBATCH --time=00:10:00
#SBATCH -p shared
#SBATCH --job-name=figures
#SBATCH --output=logs/figures_%j.out
#SBATCH --error=logs/figures_%j.err

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.sh"
module load r

cd "$MORPHOSIM_DIR"

echo "=== $(date '+%Y-%m-%d %H:%M:%S') starting results_figures_extra ==="
Rscript run/misc/results_figures_extra.R
echo "=== $(date '+%Y-%m-%d %H:%M:%S') finished results_figures_extra ==="
