#!/usr/bin/env bash
# Packar dist/Transkribera.app i en .dmg med genväg till Program-mappen.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-dev}"
STAGING="$(mktemp -d)"
cp -R dist/Transkribera.app "$STAGING/"
ln -s /Applications "$STAGING/Program"
DMG="dist/Transkribera-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "Transkribera" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"
echo "Klar: $DMG"
