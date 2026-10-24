#!/bin/sh
# One heavy GPU job (WebKit export, SpriteKit harness) at a time on this Mac, across sessions: several at once crashed WindowServer (2026-10-24).
[ -n "${HOUSE_GPU_LOCKED:-}" ] || HOUSE_GPU_LOCKED=1 exec lockf -k /tmp/agents-notch-house-gpu.lock sh "$0" "$@"
# Builds the SpriteKit house harness (proof / snapdemo / idle / demo) into .build/scene-proof/harness.
set -eu
cd "$(dirname "$0")/../.."
P=.build/scene-proof
mkdir -p "$P/obj"
xcrun swiftc -O -target arm64-apple-macos14.0 -parse-as-library -module-name NotchCore -emit-module \
  -emit-module-path "$P/obj/NotchCore.swiftmodule" -emit-library -static -o "$P/obj/libNotchCore.a" Sources/NotchCore/*.swift
xcrun swiftc -O -target arm64-apple-macos14.0 -I "$P/obj" -L "$P/obj" -lNotchCore -o "$P/harness" \
  scripts/house-atlas/harness/main.swift Sources/AgentsNotch/HouseParts.swift Sources/AgentsNotch/HouseLight.swift Sources/AgentsNotch/HouseScene2*.swift Sources/AgentNotchSaver/SaverSpriteHouse.swift
