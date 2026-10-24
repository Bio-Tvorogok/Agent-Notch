#!/bin/sh
# One heavy GPU job (WebKit export, SpriteKit harness) at a time on this Mac, across sessions: several at once crashed WindowServer (2026-10-24).
[ -n "${HOUSE_GPU_LOCKED:-}" ] || HOUSE_GPU_LOCKED=1 exec lockf -k /tmp/agents-notch-house-gpu.lock sh "$0" "$@"
# Proves the real agents of the SpriteKit house against the page: replays behaviour fixtures (Tests/Fixtures/house-behaviour) through
# the page (real setAgents, the fixtures' seed and 50 ms steps) and through HouseBehaviour + HouseScene2, and compares the frames at a
# few sample times with the same gates as scene-proof.sh plus gates on the agents' own pixels.
# Output: .build/scene-proof/live-ref (page frames), .build/scene-proof/live-out (<case>-t<ms>-side.png / -diff.png / -scene.png).
# Exit status: the harness exits 3 when any sample is over a gate.
set -eu
cd "$(dirname "$0")/../.."
P=.build/scene-proof
mkdir -p .build/house-atlas "$P/obj" "$P/live-out" "$P/live-ref" "$P/junk"
xcrun swiftc -O -o .build/house-atlas/export scripts/house-atlas/export.swift
# case:hour:sample times (ms); the page and the scene both stop at every sample
# `label=fixture:hour:times` runs a fixture again under another label (another hour: the night lamps, the stars)
CASES=${LIVE_CASES:-'03-projects:12:3500,9500,14000,46000 subagents-return:20:5000,8000,17500 churn-growth:12:5500,8200,10500,20000 marks:12:4000,9000,25000 fire-handover:12:12000,22000,26000,31500,45000 celebrate-mail-leave:12:10500,25000,36750,50000 yard-fetch:12:100000,120000,150000 quiet-day:12:95000,193000 night-projects=03-projects:22:9500,14000,46000 night-yard=yard-fetch:23:100000,150000 winter-projects=03-projects:12:9500,46000:winter spring-projects=03-projects:12:9500,46000:spring summer-projects=03-projects:12:9500:summer winter-night=03-projects:22:9500:winter spring-night=yard-fetch:23:100000:spring sky-life:12:60000,100000,200000,260000 night-sky=sky-life:23:100000 shower-escort:12:20000,37750,56000 pets-work:12:74500,166250'}
python3 - "$CASES" "$P/x" > "$P/live-cases.js" <<'PY'
import json, sys
cases = []
for spec in sys.argv[1].split():
    name, hour, samples, *extra = spec.split(':')   # optional 4th field: season, 5th: weather
    import os
    label, name = (name.split('=') + [None])[:2] if '=' in name else (name, name)
    d = json.load(open(next(f for f in ('Tests/Fixtures/%s/%s.json' % (x, name) for x in ('house-behaviour', 'house-life', 'house-overlays', 'house-sky')) if os.path.exists(f))))['input']
    cases.append({'name': label, 'fixture': name, 'seed': d['seed'], 'hour': float(hour), 'samples': [int(x) for x in samples.split(',')], 'season': extra[0] if extra else 'autumn', 'weather': extra[1] if len(extra) > 1 else 'clear',
                  'events': [{'at': e['at'], 'rows': e['rows']} for e in d['events'] if 'rows' in e]})
print('window.__LIVE_CASES = ' + json.dumps(cases) + ';')
open(os.path.join(os.path.dirname(sys.argv[2]) if len(sys.argv) > 2 else '.', 'live-aliases.txt'), 'w').write(''.join('%s %s\n' % (c['name'], c['fixture']) for c in cases if c['name'] != c['fixture']))
PY
cat "$P/live-cases.js" scripts/house-atlas/harness/live-ref.js > "$P/live-run.js"
rm -f "$P"/live-ref/live-*
HOUSE_REF_ONLY=1 .build/house-atlas/export room/index.html "$P/live-run.js" "$P/junk" 12 parts "$P/live-ref"
xcrun swiftc -O -target arm64-apple-macos14.0 -parse-as-library -module-name NotchCore -emit-module \
  -emit-module-path "$P/obj/NotchCore.swiftmodule" -emit-library -static -o "$P/obj/libNotchCore.a" Sources/NotchCore/*.swift
xcrun swiftc -O -target arm64-apple-macos14.0 -I "$P/obj" -L "$P/obj" -lNotchCore -o "$P/harness" \
  scripts/house-atlas/harness/main.swift Sources/AgentsNotch/HouseParts.swift Sources/AgentsNotch/HouseLight.swift Sources/AgentsNotch/HouseScene2*.swift Sources/AgentNotchSaver/SaverSpriteHouse.swift
rm -rf "$P/fixtures"; mkdir -p "$P/fixtures"
for d in house-behaviour house-life house-overlays house-sky; do for f in Tests/Fixtures/$d/*.json; do ln -sf "$PWD/$f" "$P/fixtures/"; done; done
while read -r a f; do ln -sf "$PWD/$(ls Tests/Fixtures/house-*/$f.json | head -1)" "$P/fixtures/$a.json"; done < "$P/live-aliases.txt"
"$P/harness" live room/atlas "$P/live-ref" "$P/fixtures" "$P/live-out"
