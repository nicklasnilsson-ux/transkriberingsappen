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

codesign --force --deep --options runtime --timestamp \
  --entitlements Transkribera/Resources/Transkribera.entitlements \
  --sign "$MACOS_SIGNING_IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

if [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]; then
  ditto -c -k --keepParent "$APP" "$RUNNER_TEMP/notarize.zip"
  xcrun notarytool submit "$RUNNER_TEMP/notarize.zip" \
    --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD" --wait
  xcrun stapler staple "$APP"
else
  echo "Notariseringsuppgifter saknas – hoppar över notarisering."
fi
