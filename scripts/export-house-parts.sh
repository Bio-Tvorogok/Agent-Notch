#!/bin/sh
# One heavy GPU job (WebKit export, SpriteKit harness) at a time on this Mac, across sessions: several at once crashed WindowServer (2026-10-24).
[ -n "${HOUSE_GPU_LOCKED:-}" ] || HOUSE_GPU_LOCKED=1 exec lockf -k /tmp/agents-notch-house-gpu.lock sh "$0" "$@"
# Cuts room/index.html into REUSABLE PARTS for the SpriteKit house (positioned against their own origin, not the
# screen): room/atlas/parts.json (manifest) and parts-N.png. Same page, same WKWebView as export-house-atlas.sh.
# It also re-composes frames from the parts and compares them with the page's own: .build/parts-check/*.png.
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/house-atlas .build/parts-check
xcrun swiftc -O -o .build/house-atlas/export scripts/house-atlas/export.swift
SEASON=${SEASON:-autumn}; ATLAS=room/atlas; [ "$SEASON" = autumn ] || ATLAS=room/atlas-$SEASON
HOUSE_SEASON=$SEASON .build/house-atlas/export room/index.html scripts/house-atlas/parts.js "$ATLAS" "${HOUR:-12}" parts .build/parts-check
# Check the persisted manifest and file set as well as the in-page gate.
ATLAS=$ATLAS python3 - <<'PY'
import json
from pathlib import Path
import os
out = Path(os.environ.get('ATLAS', 'room/atlas'))
m = json.loads((out / 'parts.json').read_text())
expected = {'parts.json'} | {p[k] for p in m['pages'] for k in ('file', 'fileE')}
actual = {'parts.json'} | {p.name for p in out.glob('parts-*.png')}
assert actual == expected, f'parts file set mismatch: {actual ^ expected}'
assert all((out / name).stat().st_size > 0 for name in expected), 'empty output'
counts, hours = [0, 1, 2, 3, 5, 14], [0, 6.5, 10, 12, 19.25, 20, 21, 23]
proof = {(p['projects'], p['hour']): p for p in m['proof']}
assert len(m['proof']) == 48 and set(proof) == {(n, h) for n in counts for h in hours}, 'incomplete proof matrix'
assert all(p['housePixels'] > 0 and p['houseDiffOver24'] / p['housePixels'] <= .001 for p in proof.values()), 'parts proof exceeds 0.1%'
assert m['firstCutProof']['sameSilhouette'] and len(set(m['firstCutProof']['opaquePixels'])) == 1, 'clipped first cut'
assert proof[2, 20]['poses'] == ['claude/stand.0', 'claude/walk.1', 'claude/work.1', 'claude/fire.1'], 'missing pose proof'
print('House pixels off by >24 (%); gate <= 0.1%')
print('n/hour  ' + ' '.join(f'{h:>8}' for h in hours))
for n in counts:
    print(f'{n:>6}  ' + ' '.join(f"{proof[n,h]['pctHouse']:8.4f}" for h in hours))
# The proof numbers move with the page's live frame; keep them out of the renderer's manifest so reruns are byte-identical.
Path('.build/parts-check/proof.json').write_text(json.dumps({k: m.pop(k) for k in ('proof', 'proofNote', 'proofGate', 'firstCutProof')}, indent=1))
(out / 'parts.json').write_text(json.dumps(m, separators=(',', ':'), ensure_ascii=False, sort_keys=True))
PY
