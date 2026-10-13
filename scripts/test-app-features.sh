#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/checks
xcrun swiftc -O -I build/obj -L build/obj -lNotchCore \
  -o .build/checks/app-feature-checks Tests/AppFeatureChecks/main.swift
.build/checks/app-feature-checks
