#!/usr/bin/env bash
# Kontrollerar att varje modell som visas i modellväljaren går att ladda ner: zip-filen
# ska finnas i sin release (kb-whisper-v1, pianissimo-v1) och WhisperKit-varianten på
# Hugging Face. Listan tas från appens egen katalog (WhisperModel.offered), så en modell
# som läggs till i väljaren innan den är publicerad stoppar bygget. Se docs/KONTROLLER.md.
set -euo pipefail
cd "$(dirname "$0")/.."

DOWNLOADER=Transkribera/Services/ModelDownloader.swift
release_const() { sed -nE "s/.*static let $1 = \"([^\"]+)\".*/\1/p" "$DOWNLOADER"; }
RELEASES_URL="$(sed -nE 's/.*static let releasesURL = URL\(string: "([^"]+)"\).*/\1/p' "$DOWNLOADER")"
KB_RELEASE="$(release_const kbRelease)"
KLANG_RELEASE="$(release_const pianissimoRelease)"
WHISPERKIT_TREE="https://huggingface.co/api/models/argmaxinc/whisperkit-coreml/tree/main"
if [[ -z "$RELEASES_URL" || -z "$KB_RELEASE" || -z "$KLANG_RELEASE" ]]; then
  echo "::error::Hittade inte release-adresserna i $DOWNLOADER"
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
xcrun swiftc -swift-version 5 -o "$WORK/list-models" \
  Transkribera/Models/ModelCatalog.swift scripts/check-models/main.swift
"$WORK/list-models" > "$WORK/models.txt"
[[ -s "$WORK/models.txt" ]] || { echo "::error::Modellistan är tom"; exit 1; }

failed=0
exists() { curl -fsSL -r 0-0 --retry 3 --retry-all-errors -o /dev/null "$1"; }
while read -r kind name; do
  case "$kind" in
    kb) url="${RELEASES_URL%/}/$KB_RELEASE/$name"; exists "$url" && ok=1 || ok=0 ;;
    klang) url="${RELEASES_URL%/}/$KLANG_RELEASE/$name"; exists "$url" && ok=1 || ok=0 ;;
    whisperkit)
      url="$WHISPERKIT_TREE/openai_whisper-$name"
      files="$(curl -fsSL --retry 3 --retry-all-errors "$url" || true)"
      grep -q '"path"' <<<"$files" && ok=1 || ok=0 ;;
    *) echo "::error::Okänd källa: $kind $name"; failed=1; continue ;;
  esac
  if [[ $ok == 1 ]]; then
    echo "OK      $name  ($url)"
  else
    echo "::error::Modellen $name visas i väljaren men går inte att ladda ner: $url"
    failed=1
  fi
done < "$WORK/models.txt"
exit $failed
