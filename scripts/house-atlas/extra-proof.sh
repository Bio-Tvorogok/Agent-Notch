#!/bin/sh
# Proves the extra screen's native sky and city (HouseScene2.extraScreen) against the page's own ?scene=extra frames: the page is loaded with
# scene=extra (export.swift, HOUSE_SCENE=extra), its islets removed (they come with the islets export), and recorded at 4 hours (harness/extra-ref.js);
# the scene renders the same and the whole frame is compared with the scene proof's frame gates.
# Output: .build/extra-proof/ref (page frames), .build/extra-proof/out (<hour>-side.png: page | scene, -diff.png). Exit status: 3 over a gate.
set -eu
cd "$(dirname "$0")/../.."
P=.build/extra-proof
mkdir -p .build/house-atlas "$P/obj" "$P/out" "$P/ref" "$P/junk"
xcrun swiftc -O -o .build/house-atlas/export scripts/house-atlas/export.swift
{ echo "window.__REF_FIXTURES = [12, 19.416666666666668, 23, 6.5];"; cat scripts/house-atlas/harness/extra-ref.js; } > "$P/ref-run.js"
rm -f "$P"/ref/ref-*
HOUSE_SCENE=extra HOUSE_REF_ONLY=1 .build/house-atlas/export room/index.html "$P/ref-run.js" "$P/junk" 12 parts "$P/ref"
xcrun swiftc -O -target arm64-apple-macos14.0 -parse-as-library -module-name NotchCore -emit-module \
  -emit-module-path "$P/obj/NotchCore.swiftmodule" -emit-library -static -o "$P/obj/libNotchCore.a" Sources/NotchCore/*.swift
xcrun swiftc -O -target arm64-apple-macos14.0 -I "$P/obj" -L "$P/obj" -lNotchCore -o "$P/harness" \
  scripts/house-atlas/harness/main.swift Sources/AgentsNotch/HouseParts.swift Sources/AgentsNotch/HouseLight.swift Sources/AgentsNotch/HouseScene2*.swift Sources/AgentNotchSaver/SaverSpriteHouse.swift
"$P/harness" extra room/atlas "$P/ref" "$P/out"
