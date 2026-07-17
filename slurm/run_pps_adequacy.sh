#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --mem=8G
#SBATCH --time=08:00:00
#SBATCH -p shared
#SBATCH --job-name=pps_adequacy
#SBATCH --output=/nobackup/djfb16/morphosim/logs/pps_adequacy_%j.out
#SBATCH --error=/nobackup/djfb16/morphosim/logs/pps_adequacy_%j.err


SCENARIO="${1:-}"
MODEL="${2:-}"
BRANCH="restore-75bb2e8"

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
  git checkout "$BRANCH"
  git add results/pps_adequacy.rds results/pps_adequacy.csv

  if ! git diff --cached --quiet; then
    git commit -m "pps_adequacy: results $(date '+%Y-%m-%d %H:%M')"
    git pull --rebase origin "$BRANCH"
    if git push origin "$BRANCH"; then
      echo "Pushed PPS adequacy results."
    else
      echo "WARNING: push failed. Push manually with:"
      echo "  cd /nobackup/djfb16/the-matrix && git push origin $BRANCH"
    fi
  else
    echo "No changes to commit."
  fi
else
  echo "Per-model/scenario run -- not pushing. Merge per-model files first."
fi
