#!/bin/sh
# The screen saver's SpriteKit house (Sources/AgentNotchSaver/SaverSpriteHouse.swift) built from a snapshot, offscreen: built for the snapshot's
# projects, follows a later one, draws a house, and draws spring, and gives way to the page for another layout or a missing atlas.
# Output: .build/scene-proof/saver.png. Exit status: 3 when a gate fails. (The ScreenSaverView glue cannot run without a screen saver host.)
set -eu
cd "$(dirname "$0")/../.."
sh scripts/house-atlas/build-harness.sh
.build/scene-proof/harness saver room/atlas .build/scene-proof/saver.png
