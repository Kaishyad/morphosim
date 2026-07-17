#!/bin/bash
# Push inference results for a model to GitHub
#
# NOTE: this is hardcoded to mk/model1 only and duplicates what
# push_when_done.sh already does generically for any scenario/model.
# Kept as-is (branch fixed) in case something still calls it directly,
# but push_when_done.sh mk model1 does the same job and stays in sync
# with future changes to the push logic -- consider retiring this file.

MODEL=model1
SCENARIO=mk
BRANCH="restore-75bb2e8"

cd /nobackup/djfb16/the-matrix
git checkout "$BRANCH"

for tl in 1.00 1.50 2.50 5.00; do
  for gl in 0.10 0.25 0.50 1.00; do
    for c in 25 50 100 200; do
      grid="tl${tl}_gl${gl}_c${c}"
      git add results/${SCENARIO}/${grid}/*/${MODEL}/ 2>/dev/null
      git commit -m "${SCENARIO} ${MODEL} ${grid}" 2>/dev/null || true
    done
  done
  git push origin "$BRANCH"
  echo "Pushed tl${tl}"
done

echo "All done."
