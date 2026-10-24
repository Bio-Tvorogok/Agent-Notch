#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
out="${HOUSE_CHECK_DIR:-.build/checks/house}"
mkdir -p "$out"
python3 - "$out/ExpiryHarness.swift" <<'PY'
from pathlib import Path
import sys
s=Path('Sources/AgentsNotch/Store.swift').read_text()
methods=s[s.index('    private func hookOutput('):s.index('    private func updateLivenessTimer(')]
publication=s[s.index('struct HookOutputPublication {'):]
Path(sys.argv[1]).write_text('''import Foundation
import NotchCore
@MainActor final class ExpiryHarness {
    var agents: [Agent] = []
    var hooks = HookState()
    var hookPublication = HookOutputPublication()
    var hookExpiryTimer: Timer?
    let settings = ExpirySettings()
    let names = ExpiryNames()
    let objectWillChange = ExpiryChanges()
'''+methods.replace('private func ', 'func ')+'}\n'+publication)
PY
xcrun swiftc -parse-as-library -I build/obj -L build/obj -lNotchCore -o "$out/expiry-check" "$out/ExpiryHarness.swift" Tests/HouseChecks/expiry-main.swift
"$out/expiry-check"
