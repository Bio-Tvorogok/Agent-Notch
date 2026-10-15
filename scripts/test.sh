#!/bin/sh
# Builds NotchCore together with the checks into one binary and runs it. Exit code is the verdict.
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/checks
xcrun swiftc -O -o .build/checks/core-checks Sources/NotchCore/*.swift Tests/CoreChecks/*.swift
.build/checks/core-checks
sh scripts/test-keep-awake.sh

python3 -m unittest discover -s Tests/UpdateChecks

python3 -m unittest discover -s Tests/ReleaseSkillChecks
