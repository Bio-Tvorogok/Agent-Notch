#!/bin/sh
# Both start paths of RoomWallpaper (the page and SpriteKit) must install the pointer: the desktop hit targets, the global monitor and
# the pinch tap all live in startPointer(), and each path must call it. (Once SpriteKit returned early and nothing answered the pointer.)
# A source check: the app target cannot run headless, so this reads the function bodies.
set -eu
cd "$(dirname "$0")/.."
F=Sources/AgentsNotch/RoomWallpaper.swift
body() { awk -v name="$1" '$0 ~ "func "name"\\(" {on=1} on {print} on && /^    }$/ {exit}' "$F"; }
fail=0
for fn in startSpriteKit start; do
  body "$fn" | grep -q 'startPointer()' || { echo "FAIL: $fn() does not call startPointer()"; fail=1; }
done
p=$(body startPointer)
for need in refreshDesktopHitTargets addGlobalMonitorForEvents startPinchTap; do
  echo "$p" | grep -q "$need" || { echo "FAIL: startPointer() lacks $need"; fail=1; }
done
[ $fail = 0 ] && echo "pointer wiring: both start paths install the pointer"
exit $fail
