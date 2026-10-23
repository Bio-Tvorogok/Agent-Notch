#!/bin/sh
# Main-thread cost and frame demand of the SpriteKit house, without the app: the harness drives HouseScene2.update(_:) like SKView does
# (at the rate the scene asks for, paused when it naps) over a scripted 60 s on a virtual clock.
#   scripts/house-atlas/bench.sh            the working tree; also the regression check (an idle house must rest, a steady one makes no nodes)
#   scripts/house-atlas/bench.sh <rev>      the sources and atlas of a commit (numbers only, no check), the fixtures stay the working tree's
# Fixtures: `marks` (six agents working and waiting) for work, no agents for idle and life.
set -eu
cd "$(dirname "$0")/../.."
REV=${1:-}
SECS=${SECS:-60}
P=.build/bench${REV:+-$REV}
rm -rf "$P"; mkdir -p "$P/obj" "$P/fixtures"
if [ -n "$REV" ]; then
  git archive "$REV" Sources room scripts | tar -x -C "$P"
  SRC=$P
  sed -e 's/HouseRects\.created/0/g' -e 's/; sc\.roomClockOverride = 100_000//' -e 's/\$0\.life\.hold/$0.life.hold/' scripts/house-atlas/harness/main.swift > "$P/main.swift"
  MAIN=$P/main.swift; CHECK=
else
  SRC=.; MAIN=scripts/house-atlas/harness/main.swift; CHECK=check
fi
for d in house-behaviour house-life house-overlays; do for f in Tests/Fixtures/$d/*.json; do ln -sf "$PWD/$f" "$P/fixtures/"; done; done
xcrun swiftc -O -target arm64-apple-macos14.0 -parse-as-library -module-name NotchCore -emit-module -emit-module-path "$P/obj/NotchCore.swiftmodule" \
  -emit-library -static -o "$P/obj/libNotchCore.a" "$SRC"/Sources/NotchCore/*.swift
SAVER=Sources/AgentNotchSaver/SaverSpriteHouse.swift; [ -n "${REV:-}" ] && SAVER= # an older revision has no SpriteKit saver
xcrun swiftc -O ${REV:+-D OLDREV} -target arm64-apple-macos14.0 -I "$P/obj" -L "$P/obj" -lNotchCore -o "$P/harness" "$MAIN" \
  "$SRC"/Sources/AgentsNotch/HouseParts.swift "$SRC"/Sources/AgentsNotch/HouseLight.swift "$SRC"/Sources/AgentsNotch/HouseScene2*.swift $SAVER
rc=0
for kind in ${KINDS:-walk type idle life}; do
  "$P/harness" bench "$SRC/room/atlas" "$P/fixtures" marks "$kind" "$SECS" "${REV:-tree}/$kind" ${CHECK:+$CHECK} || rc=$?
done
exit $rc
