#!/bin/sh
# Proves the pointer of the SpriteKit house against the page: the same pointer / pinch / scroll / click sequence goes to room/index.html
# (interact-ref.js, its real camera, hover and click code on a virtual clock) and to HouseScene2, and every record compares the camera
# (zoom, at, target), the overview button, the hovered agent, the hover card and the click's {open}. Two settled zoomed views are also
# compared as frames (house and agent pixels, the live proof's gates; the sky is magnified here and repainted by the page: not gated).
# Output: .build/scene-proof/interact-ref (page records and frames), .build/scene-proof/interact-out (<frame>-side.png / -diff.png).
# Exit status: the harness exits 3 when a record differs or a frame is over a gate.
set -eu
cd "$(dirname "$0")/../.."
P=.build/scene-proof
mkdir -p .build/house-atlas "$P/obj" "$P/interact-out" "$P/interact-ref" "$P/junk"
xcrun swiftc -O -o .build/house-atlas/export scripts/house-atlas/export.swift
CASES=${INTERACT_CASES:-'03-projects:12:14000'}
python3 - "$CASES" > "$P/interact-cases.js" <<'PY'
import json, sys
cases = []
for spec in sys.argv[1].split():
    name, hour, samples = spec.split(':')
    d = json.load(open('Tests/Fixtures/house-behaviour/%s.json' % name))['input']
    cases.append({'name': name, 'seed': d['seed'], 'hour': float(hour), 'samples': [int(x) for x in samples.split(',')],
                  'events': [{'at': e['at'], 'rows': e['rows']} for e in d['events'] if 'rows' in e]})
print('window.__LIVE_CASES = ' + json.dumps(cases) + ';')
PY
cat "$P/interact-cases.js" scripts/house-atlas/harness/interact-ref.js > "$P/interact-run.js"
rm -f "$P"/interact-ref/interact*
HOUSE_REF_ONLY=1 .build/house-atlas/export room/index.html "$P/interact-run.js" "$P/junk" 12 parts "$P/interact-ref"
xcrun swiftc -O -target arm64-apple-macos14.0 -parse-as-library -module-name NotchCore -emit-module \
  -emit-module-path "$P/obj/NotchCore.swiftmodule" -emit-library -static -o "$P/obj/libNotchCore.a" Sources/NotchCore/*.swift
xcrun swiftc -O -target arm64-apple-macos14.0 -I "$P/obj" -L "$P/obj" -lNotchCore -o "$P/harness" \
  scripts/house-atlas/harness/main.swift Sources/AgentsNotch/HouseParts.swift Sources/AgentsNotch/HouseLight.swift Sources/AgentsNotch/HouseScene2*.swift
"$P/harness" interact room/atlas "$P/interact-ref" Tests/Fixtures/house-behaviour "$P/interact-out"
