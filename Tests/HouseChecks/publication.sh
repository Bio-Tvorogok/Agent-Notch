#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
out="${HOUSE_CHECK_DIR:-.build/checks/house}"
mkdir -p "$out"
python3 - "$out/HookOutputPublication.swift" <<'PY'
from pathlib import Path
import sys
s=Path('Sources/AgentsNotch/Store.swift').read_text()
marker='struct HookOutputPublication {'
if marker not in s: raise SystemExit('FAIL: Store has no effective-hook publication check')
Path(sys.argv[1]).write_text('import NotchCore\n'+s[s.index(marker):])
PY
xcrun swiftc -parse-as-library -I build/obj -L build/obj -lNotchCore -o "$out/publication-check" "$out/HookOutputPublication.swift" Tests/HouseChecks/publication-main.swift
"$out/publication-check"
