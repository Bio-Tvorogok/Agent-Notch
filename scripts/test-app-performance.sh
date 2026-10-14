#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/checks
xcrun swiftc -O -I build/obj -L build/obj -lNotchCore -o .build/checks/card-performance-checks \
  Sources/AgentsNotch/CardDetailModel.swift Tests/AppPerformanceChecks/card-main.swift
.build/checks/card-performance-checks
xcrun swiftc -O -o .build/checks/surface-schedule-checks \
  Sources/AgentsNotch/SurfaceTimeline.swift Tests/AppPerformanceChecks/schedule-main.swift
.build/checks/surface-schedule-checks
xcrun swiftc -O -parse-as-library -I build/obj -L build/obj -lNotchCore -o .build/checks/date-performance-checks \
  Tests/AppPerformanceChecks/date-main.swift
.build/checks/date-performance-checks
