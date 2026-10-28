#!/usr/bin/env bash
# Signerar dist/Transkribera.app inifrån och ut med samma identitet överallt.
#   codesign-app.sh -           ad hoc (standard när inget Developer ID finns)
#   codesign-app.sh "Developer ID Application: …"
# Med härdad runtime laddar macOS bara ramverk med samma Team ID som appen, så Sparkle
# (som levereras signerat av Sparkle-projektet) måste signeras om tillsammans med appen.
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="${1:--}"
APP="dist/Transkribera.app"
TIMESTAMP=()
[[ "$IDENTITY" != "-" ]] && TIMESTAMP=(--timestamp)

sign() { codesign --force --options runtime ${TIMESTAMP[@]+"${TIMESTAMP[@]}"} --sign "$IDENTITY" "$@"; }

# Sparkle: inifrån och ut, utan --deep, och Downloader.xpc behåller sina egna rättigheter.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
if [[ -d "$SPARKLE" ]]; then
  sign "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
  sign --preserve-metadata=entitlements "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
  sign "$SPARKLE/Versions/B/Autoupdate"
  sign "$SPARKLE/Versions/B/Updater.app"
  sign "$SPARKLE"
fi
# Övriga inbäddade ramverk och bibliotek.
find "$APP/Contents/Frameworks" -maxdepth 1 \( -name "*.framework" -o -name "*.dylib" \) ! -name "Sparkle.framework" -print0 2>/dev/null \
  | while IFS= read -r -d '' item; do sign "$item"; done
sign --entitlements Transkribera/Resources/Transkribera.entitlements "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
