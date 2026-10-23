#!/bin/sh
# Main-thread cost of a project joining the SpriteKit house (deliver + advanceBehaviour + the swapped-in paint), at 2, 5 and 11 projects.
# Exit status: 3 when a join costs more than 8 ms on the main thread.
set -eu
cd "$(dirname "$0")/../.."
sh scripts/house-atlas/build-harness.sh
for n in 2 5 11; do .build/scene-proof/harness addproject room/atlas "$n"; done
