#!/bin/sh
# Proves the SpriteKit house (Sources/AgentsNotch/HouseScene2*.swift) against the page itself: records the page's own frames for
# 5 fixtures (projects, hour), renders the same with HouseScene2 (the pinned capture of the parts pipeline: 1728x1117@2, insets 32/70/120, so the canvases are 1728x1117, 2304x1490 and 3456x2234 by project count), and prints the share of house pixels off by > 24.
# Output: .build/scene-proof/ref (page frames), .build/scene-proof/out (<fixture>-side.png / -diff.png / -scene.png).
set -eu
cd "$(dirname "$0")/../.."
P=${HOUSE_PROOF_DIR:-.build/scene-proof}
mkdir -p .build/house-atlas "$P/obj" "$P/out" "$P/ref" "$P/junk"
xcrun swiftc -O -o .build/house-atlas/export scripts/house-atlas/export.swift
FIX=${SCENE_FIXTURES:-'[[2,12],[5,20],[5,6.5],[14,19.416666666666668],[0,12],[5,12,2],[3,18.75,3]]'}
{ echo "window.__REF_FIXTURES = $FIX;"; cat scripts/house-atlas/harness/ref.js; } > "$P/ref-run.js"
rm -f "$P"/ref/ref-*
HOUSE_REF_ONLY=1 .build/house-atlas/export room/index.html "$P/ref-run.js" "$P/junk" 12 parts "$P/ref"
xcrun swiftc -O -target arm64-apple-macos14.0 -parse-as-library -module-name NotchCore -emit-module \
  -emit-module-path "$P/obj/NotchCore.swiftmodule" -emit-library -static -o "$P/obj/libNotchCore.a" Sources/NotchCore/*.swift
xcrun swiftc -O -target arm64-apple-macos14.0 -I "$P/obj" -L "$P/obj" -lNotchCore -o "$P/harness" \
  scripts/house-atlas/harness/main.swift Sources/AgentsNotch/HouseParts.swift Sources/AgentsNotch/HouseLight.swift Sources/AgentsNotch/HouseScene2*.swift Sources/AgentNotchSaver/SaverSpriteHouse.swift
"$P/harness" proof room/atlas "$P/ref" "$P/out"

# exit status: the harness exits 3 when any fixture is above 0.1% house pixels (set -e passes it on)
