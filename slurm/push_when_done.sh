#!/bin/bash
# Push nt inference results for one model to GitHub
# Usage: bash push_models_nt.sh model1
# Defaults to model1 if no argument given.

MODEL="${1:-model1}"
SCENARIO=nt

cd /nobackup/djfb16/the-matrix

for tl in 1.00 1.50 2.50 5.00; do
  for gl in 0.10 0.25 0.50 1.00; do
    for pr in 1.00 2.50 5.00; do
      for c in 25 50 100 200; do
        grid="tl${tl}_gl${gl}_pr${pr}_c${c}"
        git add results/${SCENARIO}/${grid}/*/${MODEL}/ 2>/dev/null
        git commit -m "${SCENARIO} ${MODEL} ${grid}" 2>/dev/null || true
      done
    done
  done
  git push origin main
  echo "Pushed tl${tl} for ${MODEL}"
done

echo "All done for ${MODEL}."