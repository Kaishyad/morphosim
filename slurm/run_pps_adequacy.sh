#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --mem=8G
#SBATCH --time=08:00:00
#SBATCH -p shared
#SBATCH --job-name=pps_adequacy
#SBATCH --output=logs/pps_adequacy_%j.out
#SBATCH --error=logs/pps_adequacy_%j.err


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
SCENARIO="${1:-}"
MODEL="${2:-}"

module load r

cd "$MORPHOSIM_DIR"
echo "=== $(date '+%Y-%m-%d %H:%M:%S') starting pps_adequacy ${SCENARIO:-all}/${MODEL:-all} ==="

if [ -n "$SCENARIO" ] && [ -n "$MODEL" ]; then
  Rscript run/pps_adequacy/pps_adequacy.R --scenario "$SCENARIO" --model "$MODEL"
elif [ -n "$SCENARIO" ]; then
  Rscript run/pps_adequacy/pps_adequacy.R --scenario "$SCENARIO"
else
  Rscript run/pps_adequacy/pps_adequacy.R
fi

echo "=== $(date '+%Y-%m-%d %H:%M:%S') finished pps_adequacy ${SCENARIO:-all}/${MODEL:-all} ==="

# Only push here when running the full (unscoped) sweep -- per-model runs
# write to a separate pps_adequacy_<scenario>_<model>.rds file that still
# needs merging (no merge_pps.R exists yet; write one before scripting the
# push for per-model runs, same pattern as merge_known_answer.R).
if [ -z "$SCENARIO" ] && [ -z "$MODEL" ]; then
  cd "$MATRIX_DIR"
  git checkout "$BRANCH"
  git add results/pps_adequacy.rds results/pps_adequacy.csv

  if ! git diff --cached --quiet; then
    git commit -m "pps_adequacy: results $(date '+%Y-%m-%d')"
    git pull --rebase origin "$BRANCH"
    if git push origin "$BRANCH"; then
      echo "Pushed PPS adequacy results."
    else
      echo "WARNING: push failed. Push manually with:"
      echo "  cd "$MATRIX_DIR" && git push origin $BRANCH"
    fi
  else
    echo "No changes to commit."
  fi
else
  echo "Per-model/scenario run -- not pushing. Merge per-model files first."
fi
