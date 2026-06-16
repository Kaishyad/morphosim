#!/bin/bash
# Push inference results for a given model to GitHub.
# Edit MODEL below to switch between models.
# Run from /nobackup/djfb16/the-matrix or anywhere.

MODEL=model2
SCENARIO=mk

cd /nobackup/djfb16/the-matrix

for tl in 1.00 1.50 2.50 5.00; do
  for gl in 0.10 0.25 0.50 1.00; do
    for c in 25 50 100 200; do
      grid="tl${tl}_gl${gl}_c${c}"
      git add results/${SCENARIO}/${grid}/*/${MODEL}/ 2>/dev/null
      git commit -m "${SCENARIO} ${MODEL} ${grid}" 2>/dev/null || true
    done
  done
  git push origin main
  echo "Pushed tl${tl}"
done

echo "All done."