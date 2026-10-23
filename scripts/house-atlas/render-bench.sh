#!/bin/sh
# The real per-frame cost of drawing the SpriteKit house, without a window: the harness renders the app's screen-sized scene
# (1728x1117 points at 2x) with SKRenderer and Metal into an offscreen texture, in real time at the rate the scene asks for (and
# napping when it would), and prints the process CPU, the frames drawn per second, the main-thread ms per frame and the process's
# instructions and cycles per second (proc_pid_rusage). CPU % follows the clock the cores run at, so compare instructions and cycles.
# `floor` is the same loop drawing and updating nothing: what the harness itself costs.
#   scripts/house-atlas/render-bench.sh            walk, crowd (14 agents moving), type, idle and floor over SECS (default 40) seconds each, the working tree
#   scripts/house-atlas/render-bench.sh <rev>      the house sources and atlas of a commit, measured by the working tree's harness
#   KINDS="walk" SECS=60 ROUNDS=3 scripts/house-atlas/render-bench.sh
set -eu
cd "$(dirname "$0")/../.."
REV=${1:-}
SECS=${SECS:-40}
P=.build/render-bench${REV:+-$REV}
rm -rf "$P"; mkdir -p "$P/obj" "$P/fixtures"
if [ -n "$REV" ]; then
  git archive "$REV" Sources room | tar -x -C "$P"; SRC=$P
  # an older revision lacks the scene's wallClock hook that pins the hour: the same two lines are added to its copy
  if ! grep -q wallClock "$P/Sources/AgentsNotch/HouseScene2.swift"; then
    sed -i '' 's/d = Date(), h = c.component/d = wallClock(), h = c.component/' "$P/Sources/AgentsNotch/HouseScene2Movers.swift"
    sed -i '' 's/^    var lastMinute = -1$/    var lastMinute = -1; var wallClock: () -> Date = { Date() }/' "$P/Sources/AgentsNotch/HouseScene2.swift"
  fi
else SRC=.; fi
for d in house-behaviour house-life house-overlays; do for f in Tests/Fixtures/$d/*.json; do ln -sf "$PWD/$f" "$P/fixtures/"; done; done
xcrun swiftc -O -target arm64-apple-macos14.0 -parse-as-library -module-name NotchCore -emit-module -emit-module-path "$P/obj/NotchCore.swiftmodule" \
  -emit-library -static -o "$P/obj/libNotchCore.a" "$SRC"/Sources/NotchCore/*.swift
xcrun swiftc -O -target arm64-apple-macos14.0 -I "$P/obj" -L "$P/obj" -lNotchCore -o "$P/harness" scripts/house-atlas/harness/main.swift \
  "$SRC"/Sources/AgentsNotch/HouseParts.swift "$SRC"/Sources/AgentsNotch/HouseLight.swift "$SRC"/Sources/AgentsNotch/HouseScene2*.swift "$SRC"/Sources/AgentNotchSaver/SaverSpriteHouse.swift
r=0
while [ "$r" -lt "${ROUNDS:-1}" ]; do
  r=$((r + 1))
  for kind in ${KINDS:-walk crowd type idle floor}; do
    if [ "$kind" = crowd ]; then
      "$P/harness" render "$SRC/room/atlas" "$P/fixtures" 14-projects crowd "$SECS" "${REV:-tree}/crowd"
    elif [ "$kind" = floor ]; then
      RB_NOUPDATE=1 RB_NORENDER=1 "$P/harness" render "$SRC/room/atlas" "$P/fixtures" ${FIXTURE:-marks} walk "$SECS" "${REV:-tree}/floor"
    else
      "$P/harness" render "$SRC/room/atlas" "$P/fixtures" ${FIXTURE:-marks} "$kind" "$SECS" "${REV:-tree}/$kind"
    fi
  done
done
