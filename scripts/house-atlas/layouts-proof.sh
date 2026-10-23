#!/bin/sh
# Page vs SpriteKit, with the existing static/live pixel gates, for each layout.
# Outputs: .build/layouts-proof/<layout>/{out,live-out}/*-side.png.
set -eu
cd "$(dirname "$0")/../.."
for layout in islands steps towers; do
    export HOUSE_LAYOUT="$layout"
    export HOUSE_PROOF_DIR=".build/layouts-proof/$layout"
    # Empty tower; one project; final stacks of one/two/three rooms; many towers;
    # daylight, night, dawn and maximum room growth.
    SCENE_FIXTURES='[[0,12],[1,12],[2,12],[3,20],[4,12],[5,6.5],[14,20],[5,12,3]]' \
        sh scripts/house-atlas/scene-proof.sh
    LIVE_CASES='03-projects:12:3500,9500,14000,46000 churn-growth:20:5500,8200,10500,20000' \
        sh scripts/house-atlas/live-proof.sh
done
