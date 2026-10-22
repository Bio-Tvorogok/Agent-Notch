#!/bin/sh
# Proves the SpriteKit house (Sources/AgentsNotch/HouseScene2*.swift) against the page itself: records the page's own frames for
# 5 fixtures (projects, hour), renders the same with HouseScene2 at 2304x1490@1, and prints the share of house pixels off by > 24.
# Output: .build/scene-proof/ref (page frames), .build/scene-proof/out (<fixture>-side.png / -diff.png / -scene.png).
set -eu
cd "$(dirname "$0")/../.."
P=.build/scene-proof
mkdir -p .build/house-atlas "$P/obj" "$P/out" "$P/ref" "$P/junk"
xcrun swiftc -O -o .build/house-atlas/export scripts/house-atlas/export.swift
FIX='[[2,12],[5,20],[5,6.5],[14,19.416666666666668],[0,12]]'
{ echo "window.__REF_FIXTURES = $FIX;"; cat scripts/house-atlas/harness/ref.js; } > "$P/ref-run.js"
.build/house-atlas/export room/index.html "$P/ref-run.js" "$P/junk" 12 parts "$P/ref"
xcrun swiftc -O -target arm64-apple-macos14.0 -parse-as-library -module-name NotchCore -emit-module \
  -emit-module-path "$P/obj/NotchCore.swiftmodule" -emit-library -static -o "$P/obj/libNotchCore.a" Sources/NotchCore/*.swift
xcrun swiftc -O -target arm64-apple-macos14.0 -I "$P/obj" -L "$P/obj" -lNotchCore -o "$P/harness" \
  scripts/house-atlas/harness/main.swift Sources/AgentsNotch/HouseParts.swift Sources/AgentsNotch/HouseLight.swift Sources/AgentsNotch/HouseScene2*.swift
"$P/harness" proof room/atlas "$P/ref" "$P/out"
