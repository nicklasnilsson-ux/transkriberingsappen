#!/usr/bin/env bash
# Kör appens egna tester (TranskriberaAppTests), t.ex. att texten har samma höjd i
# visnings- och redigeringsläget. Samma låsta paket och ad hoc-signering som build-app.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

DERIVED_DATA="${DERIVED_DATA:-build}"

xcodegen generate --quiet
mkdir -p "$DERIVED_DATA"

LOCKFILE="Package.resolved"
RESOLVED="Transkribera.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
mkdir -p "$(dirname "$RESOLVED")"
cp "$LOCKFILE" "$RESOLVED"

xcodebuild \
  -project Transkribera.xcodeproj \
  -scheme Transkribera \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$DERIVED_DATA" \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  -disableAutomaticPackageResolution \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM= \
  test 2>&1 | tee "$DERIVED_DATA/xcodebuild-test.log" | (command -v xcbeautify >/dev/null && xcbeautify || cat)
