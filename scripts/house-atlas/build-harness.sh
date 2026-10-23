#!/bin/sh
# Builds the SpriteKit house harness (proof / snapdemo / idle / demo) into .build/scene-proof/harness.
set -eu
cd "$(dirname "$0")/../.."
P=.build/scene-proof
mkdir -p "$P/obj"
xcrun swiftc -O -target arm64-apple-macos14.0 -parse-as-library -module-name NotchCore -emit-module \
  -emit-module-path "$P/obj/NotchCore.swiftmodule" -emit-library -static -o "$P/obj/libNotchCore.a" Sources/NotchCore/*.swift
xcrun swiftc -O -target arm64-apple-macos14.0 -I "$P/obj" -L "$P/obj" -lNotchCore -o "$P/harness" \
  scripts/house-atlas/harness/main.swift Sources/AgentsNotch/HouseParts.swift Sources/AgentsNotch/HouseLight.swift Sources/AgentsNotch/HouseScene2*.swift Sources/AgentNotchSaver/SaverSpriteHouse.swift
