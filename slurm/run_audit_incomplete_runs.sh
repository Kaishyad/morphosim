#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --mem=4G
#SBATCH --time=01:00:00
#SBATCH -p shared
#SBATCH --job-name=audit_runs
#SBATCH --output=/nobackup/djfb16/morphosim/logs/audit_runs_%j.out
#SBATCH --error=/nobackup/djfb16/morphosim/logs/audit_runs_%j.err

# Usage: sbatch slurm/run_audit_incomplete_runs.sh [scenario] [model]

BRANCH="clean-rebuild"

SCENARIO_ARG=""
if [ -n "$1" ]; then
  SCENARIO_ARG="--scenario $1"
fi

MODEL_ARG=""
if [ -n "$2" ]; then
  MODEL_ARG="--model $2"
fi

module load r

cd /nobackup/djfb16/morphosim
echo "=== $(date '+%Y-%m-%d %H:%M:%S') starting audit_incomplete_runs ${1:-all}/${2:-all} ==="
Rscript run/audit_incomplete_runs.R $SCENARIO_ARG $MODEL_ARG
echo "=== $(date '+%Y-%m-%d %H:%M:%S') finished audit_incomplete_runs ==="

cd /nobackup/djfb16/the-matrix
git checkout "$BRANCH"
git add results/incomplete_runs_audit.csv results/requeue_from_audit.txt 2>/dev/null

if ! git diff --cached --quiet; then
  MAX_RETRIES=5
  ATTEMPT=0
  PUSHED=false
  while [ $ATTEMPT -lt $MAX_RETRIES ]; do
    ATTEMPT=$((ATTEMPT + 1))
    git pull --rebase origin "$BRANCH"
    git add results/incomplete_runs_audit.csv results/requeue_from_audit.txt 2>/dev/null
    git commit -m "audit_incomplete_runs: $(date '+%Y-%m-%d %H:%M')" 2>/dev/null || true
    if git push origin "$BRANCH"; then
      PUSHED=true
      break
    fi
    WAIT=$((RANDOM % 30 + 10))
    echo "Push failed (attempt $ATTEMPT/$MAX_RETRIES), retrying in ${WAIT}s..."
    sleep $WAIT
  done
  if [ "$PUSHED" = false ]; then
    echo "WARNING: push failed. Push manually:"
    echo "  cd /nobackup/djfb16/the-matrix && git push origin $BRANCH"
  fi
else
  echo "No changes to commit."
fi
