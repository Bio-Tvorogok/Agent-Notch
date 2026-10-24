#!/bin/sh
# The start path of RoomWallpaper (SpriteKit, the only renderer) must install the pointer: the desktop hit targets, the global monitor and
# the pinch tap all live in startPointer(), and the path must call it. (Once SpriteKit returned early and nothing answered the pointer.)
# A source check: the app target cannot run headless, so this reads the function bodies.
set -eu
cd "$(dirname "$0")/.."
F=Sources/AgentsNotch/RoomWallpaper.swift
body() { awk -v name="$1" '$0 ~ "func "name"\\(" {on=1} on {print} on && /^    }$/ {exit}' "$F"; }
fail=0
for fn in startSpriteKit; do
  body "$fn" | grep -q 'startPointer()' || { echo "FAIL: $fn() does not call startPointer()"; fail=1; }
done
p=$(body startPointer)
for need in refreshDesktopHitTargets addGlobalMonitorForEvents startPinchTap; do
  echo "$p" | grep -q "$need" || { echo "FAIL: startPointer() lacks $need"; fail=1; }
done
# Clicks and gestures use AppKit's hit test, like hover. A window list scan counts invisible click-through overlays
# (ChatGPT's layer 3 sheet once blocked every click and pinch on half the screen), so it only names the cover in the log.
m=$(body mouse)
echo "$m" | grep -q 'let bare = .*desktopIsBare\|desktopIsBare(at' && { echo "FAIL: mouse() decides bare desktop from the window list"; fail=1; }
echo "$m" | grep -q 'let bare = .*NSWindow.windowNumber(at:' || { echo "FAIL: mouse() does not use AppKit's hit test"; fail=1; }
[ $fail = 0 ] && echo "pointer wiring: the start path installs the pointer"
exit $fail
