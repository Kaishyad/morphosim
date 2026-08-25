#!/bin/bash
# Explicit push commands, no loops. Run block by block, or run the whole
# file with: bash push_remaining.sh
# It will NOT stop automatically on a failed push (no set -e), so watch
# the output as it runs and check `git status` if anything looks off.

cd /nobackup/djfb16/the-matrix

### results/nt — tl1.50 ###
git add results/nt/tl1.50_gl0.10_pr1.00_*
git commit -m "results nt tl1.50 gl0.10 pr1.00"
git push origin clean-rebuild

git add results/nt/tl1.50_gl0.10_pr2.50_*
git commit -m "results nt tl1.50 gl0.10 pr2.50"
git push origin clean-rebuild

git add results/nt/tl1.50_gl0.10_pr5.00_*
git commit -m "results nt tl1.50 gl0.10 pr5.00"
git push origin clean-rebuild

git add results/nt/tl1.50_gl0.25_pr1.00_*
git commit -m "results nt tl1.50 gl0.25 pr1.00"
git push origin clean-rebuild

git add results/nt/tl1.50_gl0.25_pr2.50_*
git commit -m "results nt tl1.50 gl0.25 pr2.50"
git push origin clean-rebuild

git add results/nt/tl1.50_gl0.25_pr5.00_*
git commit -m "results nt tl1.50 gl0.25 pr5.00"
git push origin clean-rebuild

git add results/nt/tl1.50_gl0.50_pr1.00_*
git commit -m "results nt tl1.50 gl0.50 pr1.00"
git push origin clean-rebuild

git add results/nt/tl1.50_gl0.50_pr2.50_*
git commit -m "results nt tl1.50 gl0.50 pr2.50"
git push origin clean-rebuild

git add results/nt/tl1.50_gl0.50_pr5.00_*
git commit -m "results nt tl1.50 gl0.50 pr5.00"
git push origin clean-rebuild

git add results/nt/tl1.50_gl1.00_pr1.00_*
git commit -m "results nt tl1.50 gl1.00 pr1.00"
git push origin clean-rebuild

git add results/nt/tl1.50_gl1.00_pr2.50_*
git commit -m "results nt tl1.50 gl1.00 pr2.50"
git push origin clean-rebuild

git add results/nt/tl1.50_gl1.00_pr5.00_*
git commit -m "results nt tl1.50 gl1.00 pr5.00"
git push origin clean-rebuild

### results/nt — tl2.50 ###
git add results/nt/tl2.50_gl0.10_pr1.00_*
git commit -m "results nt tl2.50 gl0.10 pr1.00"
git push origin clean-rebuild

git add results/nt/tl2.50_gl0.10_pr2.50_*
git commit -m "results nt tl2.50 gl0.10 pr2.50"
git push origin clean-rebuild

git add results/nt/tl2.50_gl0.10_pr5.00_*
git commit -m "results nt tl2.50 gl0.10 pr5.00"
git push origin clean-rebuild

git add results/nt/tl2.50_gl0.25_pr1.00_*
git commit -m "results nt tl2.50 gl0.25 pr1.00"
git push origin clean-rebuild

git add results/nt/tl2.50_gl0.25_pr2.50_*
git commit -m "results nt tl2.50 gl0.25 pr2.50"
git push origin clean-rebuild

git add results/nt/tl2.50_gl0.25_pr5.00_*
git commit -m "results nt tl2.50 gl0.25 pr5.00"
git push origin clean-rebuild

git add results/nt/tl2.50_gl0.50_pr1.00_*
git commit -m "results nt tl2.50 gl0.50 pr1.00"
git push origin clean-rebuild

git add results/nt/tl2.50_gl0.50_pr2.50_*
git commit -m "results nt tl2.50 gl0.50 pr2.50"
git push origin clean-rebuild

git add results/nt/tl2.50_gl0.50_pr5.00_*
git commit -m "results nt tl2.50 gl0.50 pr5.00"
git push origin clean-rebuild

git add results/nt/tl2.50_gl1.00_pr1.00_*
git commit -m "results nt tl2.50 gl1.00 pr1.00"
git push origin clean-rebuild

git add results/nt/tl2.50_gl1.00_pr2.50_*
git commit -m "results nt tl2.50 gl1.00 pr2.50"
git push origin clean-rebuild

git add results/nt/tl2.50_gl1.00_pr5.00_*
git commit -m "results nt tl2.50 gl1.00 pr5.00"
git push origin clean-rebuild

### results/nt — tl5.00 ###
git add results/nt/tl5.00_gl0.10_pr1.00_*
git commit -m "results nt tl5.00 gl0.10 pr1.00"
git push origin clean-rebuild

git add results/nt/tl5.00_gl0.10_pr2.50_*
git commit -m "results nt tl5.00 gl0.10 pr2.50"
git push origin clean-rebuild

git add results/nt/tl5.00_gl0.10_pr5.00_*
git commit -m "results nt tl5.00 gl0.10 pr5.00"
git push origin clean-rebuild

git add results/nt/tl5.00_gl0.25_pr1.00_*
git commit -m "results nt tl5.00 gl0.25 pr1.00"
git push origin clean-rebuild

git add results/nt/tl5.00_gl0.25_pr2.50_*
git commit -m "results nt tl5.00 gl0.25 pr2.50"
git push origin clean-rebuild

git add results/nt/tl5.00_gl0.25_pr5.00_*
git commit -m "results nt tl5.00 gl0.25 pr5.00"
git push origin clean-rebuild

git add results/nt/tl5.00_gl0.50_pr1.00_*
git commit -m "results nt tl5.00 gl0.50 pr1.00"
git push origin clean-rebuild

git add results/nt/tl5.00_gl0.50_pr2.50_*
git commit -m "results nt tl5.00 gl0.50 pr2.50"
git push origin clean-rebuild

git add results/nt/tl5.00_gl0.50_pr5.00_*
git commit -m "results nt tl5.00 gl0.50 pr5.00"
git push origin clean-rebuild

git add results/nt/tl5.00_gl1.00_pr1.00_*
git commit -m "results nt tl5.00 gl1.00 pr1.00"
git push origin clean-rebuild

git add results/nt/tl5.00_gl1.00_pr2.50_*
git commit -m "results nt tl5.00 gl1.00 pr2.50"
git push origin clean-rebuild

git add results/nt/tl5.00_gl1.00_pr5.00_*
git commit -m "results nt tl5.00 gl1.00 pr5.00"
git push origin clean-rebuild

### simulations/mk — one tl block per push (smaller than results, no model dirs) ###
git add simulations/mk/tl1.00_*
git commit -m "simulations mk tl1.00"
git push origin clean-rebuild

git add simulations/mk/tl1.50_*
git commit -m "simulations mk tl1.50"
git push origin clean-rebuild

git add simulations/mk/tl2.50_*
git commit -m "simulations mk tl2.50"
git push origin clean-rebuild

git add simulations/mk/tl5.00_*
git commit -m "simulations mk tl5.00"
git push origin clean-rebuild

### simulations/nt — one tl block per push ###
git add simulations/nt/tl1.00_*
git commit -m "simulations nt tl1.00"
git push origin clean-rebuild

git add simulations/nt/tl1.50_*
git commit -m "simulations nt tl1.50"
git push origin clean-rebuild

git add simulations/nt/tl2.50_*
git commit -m "simulations nt tl2.50"
git push origin clean-rebuild

git add simulations/nt/tl5.00_*
git commit -m "simulations nt tl5.00"
git push origin clean-rebuild

echo "DONE. Run 'git status' now to confirm everything is clean and pushed."
