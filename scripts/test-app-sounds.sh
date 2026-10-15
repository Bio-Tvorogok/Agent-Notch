#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/checks
# scripts/build.sh supplies the NotchCore module. Exclude the app's entry point.
sparkle=$(./scripts/fetch-sparkle.sh)
files=$(find Sources/AgentsNotch -name '*.swift' ! -name main.swift)
xcrun swiftc -O -F "$sparkle" -framework Sparkle -Xlinker -rpath -Xlinker "$sparkle" -I build/obj -L build/obj -lNotchCore -o .build/checks/app-sound-checks \
  $files Tests/AppSoundChecks/main.swift
.build/checks/app-sound-checks
