#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --mem=8G
#SBATCH --time=08:00:00
#SBATCH -p shared
#SBATCH --job-name=ppsample
#SBATCH --output=logs/ppsample_%j.out
#SBATCH --error=logs/ppsample_%j.err

# ppsample.sh
# Generates the RevBayes posterior predictive replicate datasets
# (results/.../<modelID>/pps/pps_*.nex) that pps_adequacy.R requires.
# Must be run BEFORE run_pps_adequacy.sh for a given scenario/model, or
# pps_adequacy.R will find an empty pps/ dir and every adequacy value
# comes back NaN (see logs/pps_adequacy_* from 2026-08-11).
#
# Usage:
#   sbatch slurm/ppsample.sh <scenario> <model> [nPPS]
#
#   sbatch slurm/ppsample.sh mk model1
#   sbatch slurm/ppsample.sh nt model1 200

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.sh"

SCENARIO="$1"
MODEL="$2"
NPPS="${3:-100}"

if [ -z "$SCENARIO" ] || [ -z "$MODEL" ]; then
  echo "Usage: sbatch slurm/ppsample.sh <mk|nt> <modelN> [nPPS]"
  exit 1
fi

module load revbayes 2>/dev/null || module load r

cd "$MORPHOSIM_DIR"
echo "=== $(date '+%Y-%m-%d %H:%M:%S') starting ppsample ${SCENARIO}/${MODEL} (nPPS=${NPPS}) ==="

# List every completed replicate for this scenario/model the same way
# convergence checking does -- i.e. only cells that actually finished
# inference (have both _run_1 and _run_2 param logs). This uses the same
# JobLogsComplete() convention as check_convergence.R so ppsample only
# touches cells that are actually ready.
Rscript -e '
  source("R/core/_setup.R")
  args <- commandArgs(trailingOnly = TRUE)
  scenario <- args[1]; model <- args[2]
  grid <- ScenarioGrid(scenario)
  for (gi in seq_len(nrow(grid))) {
    gridTag <- GridTag(grid[gi, ])
    for (rep in seq_len(N_REP)) {
      repID <- SimID(rep)
      if (JobLogsComplete(scenario, gridTag, repID, model, 2)) {
        cat(paste(scenario, gridTag, repID, model, sep = "\t"), "\n")
      }
    }
  }
' "$SCENARIO" "$MODEL" > /tmp/ppsample_combos_$$.txt

N_COMBOS=$(wc -l < /tmp/ppsample_combos_$$.txt)
echo "Found $N_COMBOS completed replicate(s) for ${SCENARIO}/${MODEL}"

i=0
while IFS=$'\t' read -r scenario gridTag repID model; do
  i=$((i+1))
  simDir="simulations/${scenario}/${gridTag}/${repID}"
  outDir="results/${scenario}/${gridTag}/${repID}/${model}"

  if [ -d "${outDir}/pps" ] && [ "$(ls -A "${outDir}/pps" 2>/dev/null)" ]; then
    echo "[$i/$N_COMBOS] ${gridTag}/${repID} -- pps/ already populated, skipping"
    continue
  fi

  echo "[$i/$N_COMBOS] ${gridTag}/${repID}: sampling..."
  rb --args "$simDir" "$outDir" "$model" "$NPPS" 0 rbScripts/PPS/ppsample.Rev \
    >> "logs/ppsample_${SCENARIO}_${MODEL}_detail.log" 2>&1
done < /tmp/ppsample_combos_$$.txt

rm -f /tmp/ppsample_combos_$$.txt
echo "=== $(date '+%Y-%m-%d %H:%M:%S') finished ppsample ${SCENARIO}/${MODEL} ==="
