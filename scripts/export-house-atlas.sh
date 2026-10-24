#!/bin/sh
# Cuts room/index.html into sprite atlases for the SpriteKit house (HouseScene2.swift uses parts.json instead): room/atlas/house-*.png,
# house.json (layers, depths, the lift, poses, routes) and reference.png (the page's own frame, to compare).
# The JS stays the art source; rerun this after changing it. HOUR picks the light (default noon).
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/house-atlas
xcrun swiftc -O -o .build/house-atlas/export scripts/house-atlas/export.swift
.build/house-atlas/export room/index.html scripts/house-atlas/export.js room/atlas "${HOUR:-12}"
