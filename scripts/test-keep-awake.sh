#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/checks
xcrun swiftc -O -parse-as-library -o .build/checks/keep-awake-checks \
  Sources/AgentsNotch/KeepAwakeModel.swift Sources/AgentsNotch/MacSleepSystem.swift \
  Sources/AgentsNotch/SleepProcessCommands.swift Sources/AgentsNotch/SleepPermissionPolicy.swift Tests/KeepAwakeChecks/main.swift
.build/checks/keep-awake-checks
