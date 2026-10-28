#!/usr/bin/env bash
# Röktest av den färdiga .dmg:n: rätt version i appen, giltig signatur och att appen
# faktiskt startar och lever i några sekunder (fångar t.ex. ramverk som inte laddas).
#   smoke-test.sh DMG VERSION BYGGNUMMER
set -euo pipefail

DMG="$1" EXPECTED_VERSION="$2" EXPECTED_BUILD="$3"
MOUNT="$(mktemp -d)"
WORK="$(mktemp -d)"
cleanup() {
  [[ -n "${PID:-}" ]] && kill "$PID" 2>/dev/null || true
  hdiutil detach "$MOUNT" -quiet 2>/dev/null || true
}
trap cleanup EXIT

hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MOUNT" -quiet
cp -R "$MOUNT/Transkribera.app" "$WORK/"
APP="$WORK/Transkribera.app"
PLIST="$APP/Contents/Info.plist"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
echo "Appens version: $version ($build)"
if [[ "$version" != "$EXPECTED_VERSION" || "$build" != "$EXPECTED_BUILD" ]]; then
  echo "::error::Fel version i appen: $version ($build), förväntade $EXPECTED_VERSION ($EXPECTED_BUILD)."
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$APP"

LOG="$WORK/launch.log"
"$APP/Contents/MacOS/Transkribera" >"$LOG" 2>&1 &
PID=$!
sleep 15
if ! kill -0 "$PID" 2>/dev/null; then
  wait "$PID" || status=$?
  echo "::error::Appen avslutades direkt efter start (status ${status:-0})."
  cat "$LOG"
  ls -t ~/Library/Logs/DiagnosticReports/Transkribera* 2>/dev/null | head -1 | xargs -I{} head -60 {} || true
  exit 1
fi
echo "Appen startade och körs fortfarande efter 15 sekunder."
