# Transkribera

En native macOS-app för att transkribera ljud och video **helt lokalt** på din Mac, i stil med MacWhisper. Byggd med Swift/SwiftUI och [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift) (OpenAI Whisper optimerat för Apple Silicon via CoreML).

## Funktioner

- **Dra och släpp** eller välj ljud- och videofiler (MP4, MOV, M4A, MP3, WAV, AIFF …). Flera filer läggs i kö.
- **Lokal transkribering** med valfri Whisper-modell. Först i listan ligger [KB-Whisper](https://huggingface.co/collections/KBLab/kb-whisper) från Kungliga biblioteket, som gör betydligt färre fel på svenska; därefter OpenAI:s flerspråkiga modeller (Tiny → Large v3 Turbo). KB Medium finns också i en ordagrann variant ("strict") som stryker mindre. Dessutom finns [Pianissimo](https://huggingface.co/KlangAI/pianissimo-sv) från Klang, en svensk Parakeet-modell som körs med FluidAudio och är många gånger snabbare. Väljaren visar storlek, fart, svenskstyrka och karaktär för varje modell. Modellen laddas ner första gången.
- **Språkval**: svenska som standard, automatisk identifiering eller ett annat språk. Kan även översätta till engelska.
- **Talaridentifiering** (valfritt) med SpeakerKit: "Talare 1", "Talare 2" …, och du kan byta namn på dem.
- **Inbyggd spelare**: klicka på ett segment så hoppar uppspelningen dit. Segmentet och ordet som spelas markeras och listan följer med.
- **Redigera texten** direkt i appen.
- **Sök** i transkriberingen med markering och filtrering av träffar.
- **Export** till ren text, Markdown, SRT, WebVTT och JSON. Kopiera hela texten med ett klick.
- **Exportera för analys** (Arkiv-menyn, ⇧⌘E): en Markdown-fil per session med kort huvud och ett stycke per talarbyte med tidskod – anpassat för att tematisera t.ex. användartester i Claude. Flera transkriberingar kan exporteras på en gång.
- **Mötesinspelning**: spela in datorns systemljud (t.ex. Google Meet/Teams) och på macOS 15+ även mikrofonen. Inspelningen transkriberas när du stoppar.
- **Anonymisering** (på som standard): namn på personer, platser och organisationer, personnummer, telefonnummer, e-post, adresser, kontonummer och regnummer ersätts med t.ex. `[PERSON 1]` när du läser, kopierar och exporterar. Hälsa, religion, politisk åsikt m.m. fångas delvis. Originaltexten sparas, och du kan visa den igen med ögonknappen eller under Inställningar › Integritet. Allt sker lokalt. Ingen automatisk anonymisering är helt säker, så läs igenom texten innan du delar den.
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
- Nätverk används bara för att ladda ner modeller (OpenAI-modellerna från Hugging Face, KB-Whisper från repots release [`kb-whisper-v1`](../../releases/tag/kb-whisper-v1), Pianissimo från [`pianissimo-v1`](../../releases/tag/pianissimo-v1)). Ljudet lämnar aldrig datorn.

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
.github/workflows/kb-whisper-models.yml  CI: konverterar KB-Whisper till CoreML och publicerar dem
.github/workflows/pianissimo-model.yml   CI: konverterar Pianissimo till CoreML (FluidAudio) och publicerar den
docs/PLAN.md                    Projektplanen (reviderad)
docs/RELEASE.md                 Releaseprocess, betakanal och testning
```

## Releaser och signering

Varje push och pull request byggs på GitHub Actions (macOS 15) och en `.dmg` laddas upp som artefakt. En GitHub Release med `.dmg`-filen skapas automatiskt när `main` får en ny version, det vill säga när `MARKETING_VERSION` i `project.yml` ändras till en version som inte släppts än. Det går också att pusha en tagg som `v0.2.0`.

Från version 0.4.0 uppdaterar appen sig själv med [Sparkle](https://sparkle-project.org). Releasen lägger in den nya versionen, signerad med EdDSA-nyckeln i secreten `SPARKLE_PRIVATE_KEY`, i appcasten på branchen [`appcast`](../../tree/appcast). Betaversioner släpps från *Actions → Bygg → Run workflow → beta*. Hela processen, med testning, står i [docs/RELEASE.md](docs/RELEASE.md).

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

Transkribera är licensierad under [MIT-licensen](LICENSE). WhisperKit och SpeakerKit är MIT-licensierade av Argmax. Whisper-modellerna kommer från OpenAI (MIT) och KB-Whisper från KBLab (Apache 2.0). FluidAudio är Apache 2.0-licensierat av Fluid Inference. Pianissimo är skapad av KlangAI och licensierad under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/); appen använder en CoreML-konvertering av den.
