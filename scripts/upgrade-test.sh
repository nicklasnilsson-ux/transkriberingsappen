#!/usr/bin/env bash
# Uppgraderingstest: det som händer hos en användare när en ny version kommer.
#   1. Den förra släppta versionen installeras, startas och får en transkribering och
#      inställningar (så som en användare har dem).
#   2. Den förra versionen uppdaterar sig själv med Sparkle till det nya bygget, från en
#      lokal appcast som är signerad med den riktiga nyckeln.
#   3. Den nya versionen startar, öppnar (och ev. migrerar) databasen och ska ha kvar
#      transkriberingen och inställningarna.
#   upgrade-test.sh FÖRRA.dmg NY.zip NY_VERSION NYTT_BYGGNUMMER
# Utan SPARKLE_PRIVATE_KEY (t.ex. PR från en fork) byts appen ut för hand i steg 2.
# Kräver $PYTHON med `cryptography` (för appcast.py).
set -euo pipefail
cd "$(dirname "$0")/.."

OLD_DMG="$1" NEW_ZIP="$2" NEW_VERSION="$3" NEW_BUILD="$4"
PYTHON="${PYTHON:-python3}"
BUNDLE_ID="se.nicklasnilsson.transkribera"
CONTAINER="$HOME/Library/Containers/$BUNDLE_ID"
STORE="$CONTAINER/Data/Library/Application Support/Transkribera/Transkribera.store"
BACKUPS="$CONTAINER/Data/Library/Application Support/Transkribera/Säkerhetskopior"
PREFS="$CONTAINER/Data/Library/Preferences/$BUNDLE_ID"
MODELS="$CONTAINER/Data/Library/Application Support/Transkribera/Models"
# Nedladdade modeller, med de sökvägar och filer appen letar efter (TranscriberService.localFolder,
# isDownloaded). Ändras de måste användarna ladda ner modellerna igen; då ska testet ändras medvetet.
MODEL_FILES=(
  "kb-whisper/kb-whisper-small/AudioEncoder.mlmodelc"
  "kb-whisper/kb-whisper-small/TextDecoder.mlmodelc"
  "kb-whisper/kb-whisper-small/MelSpectrogram.mlmodelc"
  "models/argmaxinc/whisperkit-coreml/openai_whisper-large-v3-v20240930_turbo/AudioEncoder.mlmodelc"
  "models/argmaxinc/whisperkit-coreml/openai_whisper-large-v3-v20240930_turbo/TextDecoder.mlmodelc"
  "models/argmaxinc/whisperkit-coreml/openai_whisper-large-v3-v20240930_turbo/MelSpectrogram.mlmodelc"
  "pianissimo/pianissimo-sv/Preprocessor.mlmodelc"
  "pianissimo/pianissimo-sv/Encoder.mlmodelc"
  "pianissimo/pianissimo-sv/Decoder.mlmodelc"
  "pianissimo/pianissimo-sv/JointDecisionv3.mlmodelc"
  "pianissimo/pianissimo-sv/parakeet_vocab.json"
)
APP="$HOME/Applications/Transkribera.app"
WORK="$(mktemp -d)"
PORT=8765
MOUNT="$WORK/mount"

cleanup() {
  pkill -f "$APP/Contents/MacOS/Transkribera" 2>/dev/null || true
  [[ -n "${SERVER:-}" ]] && kill "$SERVER" 2>/dev/null || true
  hdiutil detach "$MOUNT" -quiet 2>/dev/null || true
}
trap cleanup EXIT

app_version() { /usr/libexec/PlistBuddy -c "Print :$1" "$APP/Contents/Info.plist" 2>/dev/null || true; }

launch() {
  "$APP/Contents/MacOS/Transkribera" >>"$WORK/app.log" 2>&1 &
  APP_PID=$!
}

# Avslutar appen som en användare gör (⌘Q), så att Sparkle hinner installera.
quit_app() {
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" || echo "osascript kunde inte avsluta appen."
  for _ in $(seq 1 30); do
    kill -0 "$APP_PID" 2>/dev/null || return 0
    sleep 1
  done
  echo "::error::Appen avslutades inte inom 30 sekunder."
  kill "$APP_PID" || true
  return 1
}

show_logs() {
  echo "--- Appens utskrifter"; cat "$WORK/app.log" || true
  [[ -f "$WORK/server.log" ]] && { echo "--- Lokal server"; cat "$WORK/server.log"; }
  echo "--- Sparkle (systemloggen)"
  log show --last 10m --style compact --predicate 'subsystem BEGINSWITH "org.sparkle-project" OR process == "Autoupdate" OR process == "Installer"' 2>/dev/null | tail -80 || true
  ls -t ~/Library/Logs/DiagnosticReports/Transkribera* 2>/dev/null | head -1 | xargs -I{} head -60 {} || true
}

die() { echo "::error::$*"; show_logs; exit 1; }

# --- 0. Rent läge: ingen app, ingen data.
pkill -f "Transkribera.app/Contents/MacOS/Transkribera" 2>/dev/null || true
rm -rf "$CONTAINER" "$APP"
killall -u "$USER" cfprefsd 2>/dev/null || true
mkdir -p "$HOME/Applications" "$MOUNT"

# --- 1. Förra versionen.
for attempt in 1 2 3 4 5; do
  hdiutil attach "$OLD_DMG" -nobrowse -readonly -mountpoint "$MOUNT" -quiet && break
  [[ $attempt == 5 ]] && die "Kunde inte montera $OLD_DMG."
  sleep $((attempt * 3))
done
ditto "$MOUNT/Transkribera.app" "$APP"
hdiutil detach "$MOUNT" -quiet
OLD_VERSION="$(app_version CFBundleShortVersionString)" OLD_BUILD="$(app_version CFBundleVersion)"
echo "Förra versionen: $OLD_VERSION ($OLD_BUILD) → ny: $NEW_VERSION ($NEW_BUILD)"

launch
for _ in $(seq 1 60); do [[ -f "$STORE" ]] && break; sleep 1; done
[[ -f "$STORE" ]] || die "Den förra versionen skapade ingen databas."
sleep 5
quit_app || die "Kunde inte avsluta den förra versionen."

"$PYTHON" scripts/upgrade_store.py seed "$STORE"
defaults write "$PREFS" anonymizeAlwaysHide -string "Testsson"
defaults write "$PREFS" language -string "sv"
# Låtsasmodeller i stället för riktiga (flera GB); appen öppnar dem inte förrän någon transkriberar.
for file in "${MODEL_FILES[@]}"; do
  mkdir -p "$(dirname "$MODELS/$file")"
  echo "uppgraderingstest" >"$MODELS/$file"
done

# --- 2. Uppdateringen.
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  SERVE="$WORK/serve"
  mkdir -p "$SERVE"
  cp "$NEW_ZIP" "$SERVE/update.zip"
  "$PYTHON" scripts/appcast.py add "$SERVE/appcast.xml" --archive "$SERVE/update.zip" \
    --url "http://127.0.0.1:$PORT/update.zip" --version "$NEW_BUILD" --short-version "$NEW_VERSION"
  "$PYTHON" -m http.server "$PORT" --bind 127.0.0.1 --directory "$SERVE" >"$WORK/server.log" 2>&1 &
  SERVER=$!

  # Peka den installerade appen mot den lokala appcasten och låt den söka direkt.
  defaults write "$PREFS" SUFeedURL -string "http://127.0.0.1:$PORT/appcast.xml"
  defaults write "$PREFS" SUEnableAutomaticChecks -bool true
  defaults write "$PREFS" SUAutomaticallyUpdate -bool true
  defaults write "$PREFS" SUHasLaunchedBefore -bool true
  defaults write "$PREFS" SUScheduledCheckInterval -int 3600
  defaults write "$PREFS" SULastCheckTime -date "2000-01-01 00:00:00 +0000"
  killall -u "$USER" cfprefsd 2>/dev/null || true

  launch
  for _ in $(seq 1 180); do grep -q "GET /update.zip" "$WORK/server.log" && break; sleep 1; done
  grep -q "GET /update.zip" "$WORK/server.log" || die "Den förra versionen hämtade aldrig uppdateringen."
  echo "Uppdateringen hämtades, väntar på att Sparkle packar upp den …"
  sleep 20
  quit_app || die "Kunde inte avsluta appen så att uppdateringen installeras."
  for _ in $(seq 1 120); do [[ "$(app_version CFBundleVersion)" == "$NEW_BUILD" ]] && break; sleep 1; done
  [[ "$(app_version CFBundleVersion)" == "$NEW_BUILD" ]] \
    || die "Sparkle installerade inte uppdateringen (appen är fortfarande $(app_version CFBundleVersion))."
  echo "Sparkle uppdaterade $OLD_VERSION ($OLD_BUILD) till $(app_version CFBundleShortVersionString) ($(app_version CFBundleVersion))."
  kill "$SERVER" 2>/dev/null || true
  defaults delete "$PREFS" SUFeedURL
  killall -u "$USER" cfprefsd 2>/dev/null || true
else
  echo "::warning::SPARKLE_PRIVATE_KEY saknas – byter ut appen för hand i stället för att testa Sparkle."
  rm -rf "$APP"
  ditto -x -k "$NEW_ZIP" "$HOME/Applications"
fi
codesign --verify --deep --strict "$APP" || die "Den uppdaterade appens signatur är ogiltig."

# --- 3. Den nya versionen med den gamla datan.
: >"$WORK/app.log"
launch
sleep 20
kill -0 "$APP_PID" 2>/dev/null || die "Den nya versionen avslutades direkt efter uppdateringen."
grep -q "Kunde inte öppna databasen" "$WORK/app.log" && die "Den nya versionen kunde inte öppna den gamla databasen."
quit_app || die "Kunde inte avsluta den nya versionen."

"$PYTHON" scripts/upgrade_store.py check "$STORE" || die "Data från den förra versionen gick förlorad."
if ls "$BACKUPS" 2>/dev/null | grep -q "kunde-inte-oppnas"; then
  die "Den nya versionen fick flytta undan den gamla databasen."
fi
ls "$BACKUPS" 2>/dev/null | grep -q "fore-bygge-$NEW_BUILD" \
  || die "Ingen säkerhetskopia av databasen gjordes före uppgraderingen."
[[ "$(defaults read "$PREFS" anonymizeAlwaysHide)" == "Testsson" ]] || die "Inställningarna från den förra versionen försvann."
for file in "${MODEL_FILES[@]}"; do
  [[ "$(cat "$MODELS/$file" 2>/dev/null)" == "uppgraderingstest" ]] \
    || die "Den nedladdade modellfilen $file finns inte kvar efter uppdateringen, så användaren måste ladda ner modellen igen."
done
echo "Uppgraderingen från $OLD_VERSION ($OLD_BUILD) fungerar: appen startar och data, inställningar och nedladdade modeller finns kvar."
