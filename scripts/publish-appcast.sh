#!/usr/bin/env bash
# Signerar uppdateringen och lägger in den i appcasten på branchen "appcast",
# som appen läser via SUFeedURL i project.yml. Körs av release-workflowen.
#   publish-appcast.sh TAGG VERSION BYGGNUMMER KANAL(stable|beta)
# Kräver SPARKLE_PRIVATE_KEY och GH_TOKEN. Python med `cryptography` ska finnas som $PYTHON.
set -euo pipefail
cd "$(dirname "$0")/.."

TAG="$1" SHORT_VERSION="$2" BUILD="$3" CHANNEL="$4"
PYTHON="${PYTHON:-python3}"
ARCHIVE="dist/Transkribera-$TAG.zip"
URL="https://github.com/$GITHUB_REPOSITORY/releases/download/$TAG/Transkribera-$TAG.zip"
NOTES="$RUNNER_TEMP/notes.md"
WORKTREE="$RUNNER_TEMP/appcast"

if [[ -z "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  echo "::warning::SPARKLE_PRIVATE_KEY saknas – appcasten uppdateras inte, så appen hittar inte den här versionen själv. Se docs/RELEASE.md."
  exit 0
fi

gh api "repos/$GITHUB_REPOSITORY/releases/generate-notes" -f tag_name="$TAG" -q .body > "$NOTES" || : > "$NOTES"

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

for attempt in 1 2 3 4 5; do
  rm -rf "$WORKTREE"; git worktree prune
  if git fetch --quiet origin appcast 2>/dev/null; then
    git worktree add --quiet --detach "$WORKTREE" FETCH_HEAD
  else
    git worktree add --quiet --detach "$WORKTREE"
    git -C "$WORKTREE" checkout --quiet --orphan appcast
    git -C "$WORKTREE" rm -rf --quiet .
    printf '# Appcast\n\nUppdateringsflödet för Transkribera (Sparkle). Genereras automatiskt av release-workflowen, se docs/RELEASE.md på main. Ändra inte för hand.\n' > "$WORKTREE/README.md"
  fi

  "$PYTHON" scripts/appcast.py add "$WORKTREE/appcast.xml" \
    --archive "$ARCHIVE" --url "$URL" --version "$BUILD" --short-version "$SHORT_VERSION" \
    $([[ "$CHANNEL" == beta ]] && echo "--channel beta") \
    --notes "$NOTES" --notes-link "https://github.com/$GITHUB_REPOSITORY/releases/tag/$TAG"

  git -C "$WORKTREE" add -A
  git -C "$WORKTREE" commit --quiet -m "Appcast: $SHORT_VERSION ($BUILD)"
  if git -C "$WORKTREE" push --quiet origin HEAD:refs/heads/appcast; then
    echo "Appcasten uppdaterad med $SHORT_VERSION ($BUILD)."
    exit 0
  fi
  echo "Push misslyckades (försök $attempt), hämtar om och försöker igen …"
  sleep $((attempt * 3))
done
echo "::error::Kunde inte uppdatera appcasten."
exit 1
