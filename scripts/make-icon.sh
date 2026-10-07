#!/usr/bin/env bash
# Regenerates Support/AppIcon.icns from scripts/make-icon.swift.
# Only needed after changing the icon; the .icns is kept in the repo.
set -euo pipefail
cd "$(dirname "$0")/.."

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
swift scripts/make-icon.swift "$tmp/AppIcon.iconset"
iconutil --convert icns --output Support/AppIcon.icns "$tmp/AppIcon.iconset"
echo "Listo: Support/AppIcon.icns"
