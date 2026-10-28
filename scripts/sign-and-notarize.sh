#!/usr/bin/env bash
# Signerar dist/Transkribera.app med ett Developer ID-certifikat och notariserar den.
# Körs bara om miljövariablerna nedan finns (t.ex. som GitHub-secrets):
#   MACOS_CERTIFICATE_P12_BASE64  – Developer ID Application-certifikat (.p12, base64)
#   MACOS_CERTIFICATE_PASSWORD    – lösenord till .p12-filen
#   MACOS_SIGNING_IDENTITY        – t.ex. "Developer ID Application: Nicklas Nilsson (TEAMID)"
#   APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD – för notarisering (app-specifikt lösenord)
set -euo pipefail
cd "$(dirname "$0")/.."

APP="dist/Transkribera.app"

if [[ -z "${MACOS_CERTIFICATE_P12_BASE64:-}" ]]; then
  echo "Inget certifikat angivet – appen förblir ad hoc-signerad."
  exit 0
fi

KEYCHAIN="$RUNNER_TEMP/signing.keychain-db"
KEYCHAIN_PASSWORD="$(uuidgen)"
echo "$MACOS_CERTIFICATE_P12_BASE64" | base64 --decode > "$RUNNER_TEMP/cert.p12"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$RUNNER_TEMP/cert.p12" -P "$MACOS_CERTIFICATE_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN"
security set-key-partition-list -S apple-tool:,apple: -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')

sign() { codesign --force --options runtime --timestamp --sign "$MACOS_SIGNING_IDENTITY" "$@"; }

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
codesign --verify --strict --verbose=2 "$APP"

if [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]; then
  ditto -c -k --keepParent "$APP" "$RUNNER_TEMP/notarize.zip"
  xcrun notarytool submit "$RUNNER_TEMP/notarize.zip" \
    --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD" --wait
  xcrun stapler staple "$APP"
else
  echo "Notariseringsuppgifter saknas – hoppar över notarisering."
fi
