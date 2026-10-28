# Transkribera

En native macOS-app för att transkribera ljud och video **helt lokalt** på din Mac, i stil med MacWhisper. Byggd med Swift/SwiftUI och [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift) (OpenAI Whisper optimerat för Apple Silicon via CoreML).

## Funktioner

- **Dra och släpp** eller välj ljud- och videofiler (MP4, MOV, M4A, MP3, WAV, AIFF …). Flera filer läggs i kö.
- **Lokal transkribering** med valfri Whisper-modell (Tiny → Large v3 Turbo). Modellen laddas ner första gången.
- **Språkval**: svenska som standard, automatisk identifiering eller ett annat språk. Kan även översätta till engelska.
- **Talaridentifiering** (valfritt) med SpeakerKit: "Talare 1", "Talare 2" …, och du kan byta namn på dem.
- **Inbyggd spelare**: klicka på ett segment så hoppar uppspelningen dit. Segmentet och ordet som spelas markeras och listan följer med.
- **Redigera texten** direkt i appen.
- **Sök** i transkriberingen med markering och filtrering av träffar.
- **Export** till ren text, Markdown, SRT, WebVTT och JSON. Kopiera hela texten med ett klick.
- **Mötesinspelning**: spela in datorns systemljud (t.ex. Google Meet/Teams) och på macOS 15+ även mikrofonen. Inspelningen transkriberas när du stoppar.
- Allt sparas lokalt med SwiftData.

## Installera

Ladda ner senaste `Transkribera-vX.Y.Z.dmg` under [Releases](../../releases) (eller från senaste bygget under *Actions → Bygg → Artifacts*). Öppna den och dra **Transkribera** till **Program**.

**Krav:** Mac med Apple Silicon (M1 eller senare) och macOS 14 Sonoma eller senare.

### Öppna en osignerad app

Tills appen signeras med ett Apple Developer ID-certifikat varnar macOS första gången du öppnar den ("Apple kan inte kontrollera …"). Gör så här en gång:

1. Försök öppna Transkribera som vanligt och tryck **Klar/OK** i varningen.
2. Öppna **Systeminställningar › Integritet och säkerhet**, scrolla ner och klicka **Öppna ändå** vid Transkribera.
3. Bekräfta med ditt lösenord.

Alternativt i Terminal: `xattr -dr com.apple.quarantine /Applications/Transkribera.app`

### Behörigheter

- **Mötesinspelning** kräver *Skärm- och systemljudsinspelning* (Systeminställningar › Integritet och säkerhet). macOS frågar första gången.
- **Mikrofon** frågas om när du spelar in med mikrofonen påslagen.
- Nätverk används bara för att ladda ner modeller från Hugging Face. Ljudet lämnar aldrig datorn.

## Bygga själv

Kräver Xcode 16 eller senare och [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
make open      # genererar Transkribera.xcodeproj och öppnar i Xcode
make app       # bygger dist/Transkribera.app från terminalen
make dmg       # bygger dist/Transkribera-dev.dmg
make test      # kör enhetstester för kärnlogiken (export, sök, tidsformat)
```

Xcode-projektet genereras från `project.yml` och checkas inte in.

### Projektstruktur

```
project.yml                     XcodeGen-specifikation (mål, beroenden, Info.plist, entitlements)
Transkribera/
  App/                          App-ingång och menykommandon
  Models/                       SwiftData-modeller, modellkatalog, inställningar
  Services/                     WhisperKit/SpeakerKit, ljudinläsning, kö, mötesinspelning
  Views/                        SwiftUI-vyer (sidopanel, startsida, detaljvy, spelare, inställningar)
Packages/TranskriberaCore/      Ren Swift-logik med tester: export, sök, tidsformat
scripts/                        Bygg, signera/notarisera och skapa .dmg
.github/workflows/build.yml     CI: testar, bygger och publicerar .dmg
docs/PLAN.md                    Projektplanen (reviderad)
```

## Releaser och signering

Varje push och pull request byggs på GitHub Actions (macOS 15) och en `.dmg` laddas upp som artefakt. När en tagg som `v0.1.0` pushas skapas en GitHub Release med `.dmg`-filen:

```sh
git tag v0.1.0 && git push origin v0.1.0
```

Appen är *ad hoc*-signerad tills följande repo-secrets läggs in, då signeras och notariseras den automatiskt så att varningen ovan försvinner (kräver Apple Developer Program):

| Secret | Innehåll |
| --- | --- |
| `MACOS_CERTIFICATE_P12_BASE64` | Developer ID Application-certifikat exporterat som .p12, base64-kodat (`base64 -i cert.p12 \| pbcopy`) |
| `MACOS_CERTIFICATE_PASSWORD` | Lösenordet till .p12-filen |
| `MACOS_SIGNING_IDENTITY` | T.ex. `Developer ID Application: Ditt Namn (TEAMID)` |
| `APPLE_ID` | Apple ID-e-post för notarisering |
| `APPLE_TEAM_ID` | Team-ID (10 tecken) |
| `APPLE_APP_PASSWORD` | App-specifikt lösenord från appleid.apple.com |

## Licens

WhisperKit och SpeakerKit är MIT-licensierade av Argmax. Whisper-modellerna kommer från OpenAI (MIT).
