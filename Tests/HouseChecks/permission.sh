#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
out="${HOUSE_CHECK_DIR:-.build/checks/house}"
mkdir -p "$out"
python3 - "$out/HousePinchPermission.swift" <<'PY'
from pathlib import Path
import sys
s=Path('Sources/AgentsNotch/SettingsHouse.swift').read_text()
marker='@MainActor enum HousePinchPermission {'
if marker not in s: raise SystemExit('FAIL: no denied-permission fallback')
Path(sys.argv[1]).write_text('import AppKit\nimport CoreGraphics\n'+s[s.index(marker):])
PY
xcrun swiftc -parse-as-library -o "$out/permission-check" "$out/HousePinchPermission.swift" Tests/HouseChecks/permission-main.swift
"$out/permission-check"
