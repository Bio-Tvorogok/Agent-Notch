#!/bin/sh
# Cuts room/index.html into REUSABLE PARTS for the SpriteKit house (positioned against their own origin, not the
# screen): room/atlas/parts.json (manifest) and parts-N.png. Same page, same WKWebView as export-house-atlas.sh.
# It also re-composes frames from the parts and compares them with the page's own: .build/parts-check/*.png.
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/house-atlas .build/parts-check
xcrun swiftc -O -o .build/house-atlas/export scripts/house-atlas/export.swift
.build/house-atlas/export room/index.html scripts/house-atlas/parts.js room/atlas "${HOUR:-12}" parts .build/parts-check
