#!/bin/bash
#bash push_when_done.sh <scenario> <model>

SCENARIO="$1"
MODEL="$2"

if [ -z "$SCENARIO" ] || [ -z "$MODEL" ]; then
  echo "Usage: bash push_model.sh <mk|nt> <modelN>"
  exit 1
fi

cd /nobackup/djfb16/the-matrix

for tl in 1.00 1.50 2.50 5.00; do
  for gl in 0.10 0.25 0.50 1.00; do
    if [ "$SCENARIO" == "mk" ]; then
      for c in 25 50 100 200; do
        grid="tl${tl}_gl${gl}_c${c}"
        git add results/${SCENARIO}/${grid}/*/${MODEL}/ 2>/dev/null
        git commit -m "${SCENARIO} ${MODEL} ${grid}" 2>/dev/null || true
      done
    else
      for pr in 1.00 2.50 5.00; do
        for c in 25 50 100 200; do
          grid="tl${tl}_gl${gl}_pr${pr}_c${c}"
          git add results/${SCENARIO}/${grid}/*/${MODEL}/ 2>/dev/null
          git commit -m "${SCENARIO} ${MODEL} ${grid}" 2>/dev/null || true
        done
      done
    fi
  done
  git push origin main
  echo "Pushed tl${tl} for ${SCENARIO} ${MODEL}"
done

echo "All done for ${SCENARIO} ${MODEL}."