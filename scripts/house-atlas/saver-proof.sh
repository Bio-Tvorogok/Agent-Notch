#!/bin/sh
# One heavy GPU job (WebKit export, SpriteKit harness) at a time on this Mac, across sessions: several at once crashed WindowServer (2026-10-24).
[ -n "${HOUSE_GPU_LOCKED:-}" ] || HOUSE_GPU_LOCKED=1 exec lockf -k /tmp/agents-notch-house-gpu.lock sh "$0" "$@"
# The screen saver's SpriteKit house (Sources/AgentNotchSaver/SaverSpriteHouse.swift) built from a snapshot, offscreen: built for the snapshot's
# projects, follows a later one, draws a house, and draws spring, and gives way to the page for another layout or a missing atlas.
# Output: .build/scene-proof/saver.png. Exit status: 3 when a gate fails. (The ScreenSaverView glue cannot run without a screen saver host.)
set -eu
cd "$(dirname "$0")/../.."
sh scripts/house-atlas/build-harness.sh
.build/scene-proof/harness saver room/atlas .build/scene-proof/saver.png
