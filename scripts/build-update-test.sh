#!/bin/sh
# Isolated integration app: real updater/settings, no agent scanning, hooks, hotkeys or user app data.
set -eu
cd "$(dirname "$0")/.."
version="${1:?stable test version}"
output="${2:?output directory}"
: "${UPDATE_PUBLIC_KEY:?separate test key required}"
: "${UPDATE_FEED_URL:?localhost test feed required}"
sparkle=$(./scripts/fetch-sparkle.sh)
app="$output/Agent Notch Update Test.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Frameworks"
ditto "$sparkle/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
xcrun swiftc -O -F "$sparkle" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  -I build/obj -L build/obj -lNotchCore -o "$app/Contents/MacOS/AgentNotchUpdateTest" \
  Sources/AgentsNotch/AppUpdates.swift Sources/AgentsNotch/SettingsUpdates.swift Tests/UpdateApp/main.swift
python3 - "$app/Contents/Info.plist" "$version" <<'PY'
from pathlib import Path
import plistlib
import sys
Path(sys.argv[1]).write_bytes(plistlib.dumps(dict(CFBundleIdentifier='com.forichok.agents-notch.updater-test', CFBundleName='Agent Notch Update Test', CFBundleExecutable='AgentNotchUpdateTest', CFBundlePackageType='APPL', CFBundleShortVersionString=sys.argv[2], CFBundleVersion=sys.argv[2], LSMinimumSystemVersion='14.0')))
PY
UPDATE_TEST_BUNDLE=1 python3 scripts/update-config.py "$app/Contents/Info.plist"
codesign --force --sign - -r='designated => identifier "com.forichok.agents-notch.updater-test"' "$app"
printf '%s\n' "$app"
