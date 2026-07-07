#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --mem=8G
#SBATCH --time=08:00:00
#SBATCH -p shared
#SBATCH --job-name=pps_adequacy
#SBATCH --output=/nobackup/djfb16/morphosim/logs/pps_adequacy_%j.out
#SBATCH --error=/nobackup/djfb16/morphosim/logs/pps_adequacy_%j.err

# Usage: sbatch slurm/run_pps_adequacy.sh [scenario] [model]
# Examples:
#   sbatch slurm/run_pps_adequacy.sh                # all scenarios/models
#   sbatch slurm/run_pps_adequacy.sh nt model8       # single model, single scenario
#
# PPS is computationally heavy (per your dissertation plan it's only meant
# to run on a REPRESENTATIVE SUBSET of the grid, not the full grid) -- so
# unlike validate_cgr.R, this is scoped per scenario/model like
# run_known_answer.sh so you can submit it as a smaller parallel batch
# rather than one long job. --time above is a starting guess; check the
# .out log on your first run and adjust.
#
# BLOCKED until the actual pps_*.nex files exist under
# <simDir>/<modelID>/pps/ -- that generation step (adapted from your
# supervisor's ppsim_ns_n_ki.Rev / ppsim_by_n_ki.Rev) needs to run BEFORE
# this script has anything to read. Running this now will just produce
# empty/NA results, not an error -- check results/pps_adequacy.csv for
# all-NA prop_adequate columns as the tell.
#
# Requires: results/convergence_summary.rds current (see run_convergence.sh).

SCENARIO="${1:-}"
MODEL="${2:-}"

module load r

cd /nobackup/djfb16/morphosim
echo "=== $(date '+%Y-%m-%d %H:%M:%S') starting pps_adequacy ${SCENARIO:-all}/${MODEL:-all} ==="

if [ -n "$SCENARIO" ] && [ -n "$MODEL" ]; then
  Rscript run/pps_adequacy.R --scenario "$SCENARIO" --model "$MODEL"
elif [ -n "$SCENARIO" ]; then
  Rscript run/pps_adequacy.R --scenario "$SCENARIO"
else
  Rscript run/pps_adequacy.R
fi

echo "=== $(date '+%Y-%m-%d %H:%M:%S') finished pps_adequacy ${SCENARIO:-all}/${MODEL:-all} ==="

# Only push here when running the full (unscoped) sweep -- per-model runs
# write to a separate pps_adequacy_<scenario>_<model>.rds file that still
# needs merging (no merge_pps.R exists yet; write one before scripting the
# push for per-model runs, same pattern as merge_known_answer.R).
if [ -z "$SCENARIO" ] && [ -z "$MODEL" ]; then
  cd /nobackup/djfb16/the-matrix
  git add results/pps_adequacy.rds results/pps_adequacy.csv

  if ! git diff --cached --quiet; then
    git pull --rebase origin main
    if git push origin main; then
      echo "Pushed PPS adequacy results."
    else
      echo "WARNING: push failed. Push manually with:"
      echo "  cd /nobackup/djfb16/the-matrix && git push origin main"
    fi
  else
    echo "No changes to commit."
  fi
else
  echo "Per-model/scenario run -- not pushing. Merge per-model files first."
fi
