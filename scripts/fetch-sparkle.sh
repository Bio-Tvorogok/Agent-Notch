#!/bin/sh
# Print the verified, pinned Sparkle distribution directory. Keep stdout machine-readable.
set -eu
cd "$(dirname "$0")/.."
version=2.10.0
checksum=c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
cache="$PWD/.build/sparkle/$version"
mkdir -p "$cache"
archive="$cache/archive.tar.xz"
if [ ! -f "$archive" ]; then
  temporary=$(mktemp "$cache/download.XXXXXX")
  trap 'rm -f "$temporary"' EXIT HUP INT TERM
  curl --fail --location --silent --show-error "https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz" -o "$temporary"
  printf '%s  %s\n' "$checksum" "$temporary" | shasum -a 256 -c - >&2
  mv "$temporary" "$archive"
fi
printf '%s  %s\n' "$checksum" "$archive" | shasum -a 256 -c - >&2
if [ ! -d "$cache/Sparkle.framework" ]; then tar -xf "$archive" -C "$cache"; fi
printf '%s\n' "$cache"
