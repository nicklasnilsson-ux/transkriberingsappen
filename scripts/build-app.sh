#!/usr/bin/env bash
# Bygger Transkribera.app (Release, Apple Silicon) till ./dist/.
# Kräver Xcode 16+ och XcodeGen (brew install xcodegen).
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA="${DERIVED_DATA:-build}"

xcodegen generate --quiet
mkdir -p "$DERIVED_DATA"

# Versionen kan skrivas över vid bygget, t.ex. för betaversioner (se docs/RELEASE.md).
VERSION_SETTINGS=()
[[ -n "${MARKETING_VERSION_OVERRIDE:-}" ]] && VERSION_SETTINGS+=("MARKETING_VERSION=$MARKETING_VERSION_OVERRIDE")
[[ -n "${BUILD_NUMBER_OVERRIDE:-}" ]] && VERSION_SETTINGS+=("CURRENT_PROJECT_VERSION=$BUILD_NUMBER_OVERRIDE")

xcodebuild \
  -project Transkribera.xcodeproj \
  -scheme Transkribera \
  -configuration "$CONFIGURATION" \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM= \
  ${VERSION_SETTINGS[@]+"${VERSION_SETTINGS[@]}"} \
  build | tee "$DERIVED_DATA/xcodebuild.log" | (command -v xcbeautify >/dev/null && xcbeautify || cat)

mkdir -p dist
rm -rf dist/Transkribera.app
cp -R "$DERIVED_DATA/Build/Products/$CONFIGURATION/Transkribera.app" dist/
echo "Klar: dist/Transkribera.app"
