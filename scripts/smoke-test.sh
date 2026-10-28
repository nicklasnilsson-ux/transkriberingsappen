#!/usr/bin/env bash
# Röktest av en färdig .dmg, så som en användare får den: nedladdad (quarantine), monterad
# och kopierad. Kontrollerar version, signaturer, att alla ramverk finns och går att ladda
# enligt macOS regler, och att appen startar och lever. Varje kontroll motsvarar ett fel vi
# haft, se docs/KONTROLLER.md.
#   smoke-test.sh DMG VERSION BYGGNUMMER
#
# OBS: GitHubs macOS-maskiner har SIP avstängt, så där laddar macOS även kod som skulle
# vägras på en vanlig Mac. Därför kontrolleras signaturreglerna statiskt nedan och inte
# bara genom att starta appen.
set -euo pipefail

DMG="$1" EXPECTED_VERSION="$2" EXPECTED_BUILD="$3"
BUNDLE_ID="se.nicklasnilsson.transkribera"
EXPECTED_FEED="https://raw.githubusercontent.com/nicklasnilsson-ux/transkriberingsappen/appcast/appcast.xml"
MOUNT="$(mktemp -d)"
WORK="$(mktemp -d)"
cleanup() {
  [[ -n "${PID:-}" ]] && kill "$PID" 2>/dev/null || true
  hdiutil detach "$MOUNT" -quiet 2>/dev/null || true
}
trap cleanup EXIT

errors=0
fail() { echo "::error::$*"; errors=$((errors + 1)); }

# Som en nedladdning från webbläsaren.
xattr -w com.apple.quarantine "0083;$(printf %x "$(date +%s)");Safari;" "$DMG"
hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MOUNT" -quiet
[[ -L "$MOUNT/Program" ]] || fail ".dmg:n saknar genvägen till Program-mappen."
ditto "$MOUNT/Transkribera.app" "$WORK/Transkribera.app"
APP="$WORK/Transkribera.app"
xattr -r -w com.apple.quarantine "0083;$(printf %x "$(date +%s)");Safari;" "$APP"
PLIST="$APP/Contents/Info.plist"
plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null || true; }

# --- Info.plist (0.4.0 och tidigare visade 1.0 (1), så Sparkle kunde inte jämföra versioner)
version="$(plist CFBundleShortVersionString)" build="$(plist CFBundleVersion)"
echo "Appens version: $version ($build)"
[[ "$version" == "$EXPECTED_VERSION" && "$build" == "$EXPECTED_BUILD" ]] \
  || fail "Fel version i appen: $version ($build), förväntade $EXPECTED_VERSION ($EXPECTED_BUILD)."
[[ "$(plist CFBundleIdentifier)" == "$BUNDLE_ID" ]] || fail "Fel bundle-id: $(plist CFBundleIdentifier)."
[[ "$(plist SUFeedURL)" == "$EXPECTED_FEED" ]] || fail "Fel SUFeedURL: $(plist SUFeedURL)."
[[ -n "$(plist SUPublicEDKey)" ]] || fail "SUPublicEDKey saknas – uppdateringar kan inte verifieras."
[[ "$(plist LSMinimumSystemVersion)" == 14.0 ]] || fail "LSMinimumSystemVersion är $(plist LSMinimumSystemVersion), förväntade 14.0."
for key in NSMicrophoneUsageDescription NSAudioCaptureUsageDescription; do
  [[ -n "$(plist "$key")" ]] || fail "$key saknas – macOS stänger appen när den ber om behörigheten."
done

# --- Signaturer
codesign --verify --deep --strict --verbose=2 "$APP" || fail "Signaturen är ogiltig."
csrutil status || true

entitlements="$(codesign -d --entitlements - --xml "$APP" 2>/dev/null || true)"
for ent in com.apple.security.app-sandbox com.apple.security.network.client com.apple.security.device.audio-input; do
  grep -q "$ent" <<<"$entitlements" || fail "Appen saknar rättigheten $ent."
done

app_details="$(codesign -dv "$APP" 2>&1)"
app_flags="$(grep -o 'flags=[^ ]*' <<<"$app_details" | head -1)"
app_team="$(sed -n 's/^TeamIdentifier=//p' <<<"$app_details")"
[[ "$app_team" == "not set" ]] && app_team=""
echo "Appen: $app_flags, Team ID ${app_team:-saknas}"
# Härdad runtime eller library validation ⇒ macOS laddar bara kod med samma Team ID.
strict_loading=0
[[ "$app_flags" == *runtime* || "$app_flags" == *library-validation* ]] && strict_loading=1

while IFS= read -r -d '' file; do
  file -b "$file" | grep -q 'Mach-O' || continue
  rel="${file#"$APP/"}"
  lipo -archs "$file" 2>/dev/null | grep -qw arm64 || fail "$rel saknar arm64."
  details="$(codesign -dv "$file" 2>&1)" || { fail "$rel är inte signerad."; continue; }
  flags="$(grep -o 'flags=[^ ]*' <<<"$details" | head -1)"
  team="$(sed -n 's/^TeamIdentifier=//p' <<<"$details")"
  [[ "$team" == "not set" ]] && team=""
  echo "$rel: $flags, Team ID ${team:-saknas}"
  # 0.4.1: ad hoc + härdad runtime ⇒ library validation utan Team ID ⇒ Sparkle laddas inte.
  if [[ "$flags" == *adhoc* && "$flags" == *runtime* ]]; then
    fail "$rel är ad hoc-signerad med härdad runtime – appen kommer inte att starta."
  fi
  # 0.4.0: Sparkle hade Sparkles eget Team ID medan appen hade ett annat.
  if [[ $strict_loading == 1 && ( "$flags" == *adhoc* || "$team" != "$app_team" ) ]]; then
    fail "$rel har inte appens Team ID (${app_team:-saknas}) – macOS vägrar ladda den."
  fi
done < <(find "$APP/Contents" -type f -print0)

# Alla ramverk som programmet länkar mot ska finnas i appen.
while read -r lib; do
  name="${lib#@rpath/}"
  [[ -e "$APP/Contents/Frameworks/$name" ]] || fail "Appen länkar mot $lib men den finns inte i Contents/Frameworks."
done < <(otool -L "$APP/Contents/MacOS/Transkribera" | awk 'NR>1 && $1 ~ /^@rpath\// {print $1}')

# Sparkles delar ska finnas och vara signerade som en enhet.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
for part in Versions/B/Autoupdate Versions/B/Updater.app Versions/B/XPCServices/Installer.xpc Versions/B/XPCServices/Downloader.xpc; do
  [[ -e "$SPARKLE/$part" ]] || fail "Sparkle saknar $part."
done

# Gatekeeper: med Developer ID ska appen godkännas av spctl; ad hoc-appar avvisas alltid
# (användaren öppnar dem första gången med högerklick → Öppna, se README).
if [[ -n "$app_team" ]]; then
  spctl --assess --type execute -vv "$APP" || fail "Gatekeeper godkänner inte appen."
else
  echo "Ad hoc-signerad: Gatekeeper kräver högerklick → Öppna första gången (väntat)."
  spctl --assess --type execute -vv "$APP" 2>&1 || true
fi

[[ $errors == 0 ]] || { echo "$errors fel hittades."; exit 1; }

# --- Start: appen ska starta och fortfarande köra efter 15 sekunder.
# En ad hoc-app godkänns av användaren första gången (högerklick → Öppna); det motsvarar
# att quarantine tas bort. En app med Developer ID startas med quarantine kvar.
[[ -z "$app_team" ]] && xattr -dr com.apple.quarantine "$APP"
reports_before="$(ls ~/Library/Logs/DiagnosticReports/ 2>/dev/null | grep -c Transkribera || true)"
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
reports_after="$(ls ~/Library/Logs/DiagnosticReports/ 2>/dev/null | grep -c Transkribera || true)"
if [[ "$reports_after" != "$reports_before" ]]; then
  echo "::error::Appen lever men har skrivit en kraschrapport."
  ls -t ~/Library/Logs/DiagnosticReports/Transkribera* | head -1 | xargs -I{} head -60 {}
  exit 1
fi
if grep -q "Kunde inte öppna databasen" "$LOG"; then
  echo "::error::Appen kunde inte öppna sin databas."
  cat "$LOG"
  exit 1
fi
echo "Appen startade och körs fortfarande efter 15 sekunder."
