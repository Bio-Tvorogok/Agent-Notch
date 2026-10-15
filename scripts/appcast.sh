#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
sparkle=$(./scripts/fetch-sparkle.sh)
python3 scripts/appcast.py "${1:?version}" "${2:-dist}" "${3:-dist/notes.md}" "$sparkle"
