#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/checks
# scripts/build.sh supplies the NotchCore module. Exclude the app's entry point.
files=$(rg --files Sources/AgentsNotch | rg '\.swift$' | rg -v '/main\.swift$')
xcrun swiftc -O -I build/obj -L build/obj -lNotchCore -o .build/checks/app-sound-checks \
  $files Tests/AppSoundChecks/main.swift
.build/checks/app-sound-checks
