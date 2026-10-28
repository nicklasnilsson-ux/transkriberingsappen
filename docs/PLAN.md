# Projektplan: Transkribera (reviderad)

Reviderad version av den ursprungliga planen för en MacWhisper-liknande app. Målen är desamma; ändringarna gör att projektet går att bygga reproducerbart (även i CI), använder WhisperKit som det ser ut idag och täcker några luckor.

## Vad som ändrades och varför

| Ursprunglig plan | Reviderat | Varför |
| --- | --- | --- |
| Skapa projektet i Xcode-GUI | **XcodeGen** (`project.yml`) + `make`/skript | Projektet kan byggas från terminalen och i GitHub Actions. Inga `.xcodeproj`-konflikter i git. |
| SPM: `github.com/argmaxinc/WhisperKit` | **`github.com/argmaxinc/argmax-oss-swift`** (produkterna `WhisperKit` + `SpeakerKit`), ≥ 1.1.1 | Repot har bytt namn och innehåller nu även SpeakerKit för talaridentifiering. |
| Modellnamn `openai_whisper-large-v3-turbo` | `large-v3-v20240930_turbo` / `large-v3-v20240930_626MB` m.fl. | Det är namnen i `argmaxinc/whisperkit-coreml`. Komprimerade Turbo är standard (bra kvalitet, mindre minne). |
| "SwiftData eller CoreData" | **SwiftData** (`Transcript` 1–n `TranscriptSegment`), kräver macOS 14 | Enklast med SwiftUI. Ordtidsstämplar lagras som JSON för stabilitet. |
| Inget språkval | **Språkväljare** (svenska som standard, auto, m.fl.) + "översätt till engelska" | Whisper gissar annars språk, vilket ofta blir fel på korta klipp. |
| Tidsstämplar per segment | **+ ordnivå** (`wordTimestamps`) | Markera ordet som spelas, dela långa undertexter snyggt, behövs för talaridentifiering. |
| "Talarens namn (om tillgängligt)" | **SpeakerKit**-diarisering (valfri) + byt namn på talare | Ger faktiska talare istället för en tom kolumn. |
| `transcribe(audioPath:)` | Egen **AVAssetReader**-avkodning till 16 kHz mono | Fungerar för video (MP4/MOV) och flerspåriga filer; samma samples återanvänds för SpeakerKit. |
| Mediefilen refereras där den ligger | **Kopieras in** i appens Application Support | App Sandbox ger bara tillfällig åtkomst; uppspelning ska fungera även nästa gång. |
| Ingen kö | **Transkriberingskö**, återupptas vid omstart, kan avbrytas | Man kan släppa flera filer på en gång. |
| Export: txt, md, srt, (json) | txt, md, srt, **vtt**, json + val av tidsstämplar | VTT behövs för webbvideo. Ren exportlogik i ett testbart Swift-paket. |
| Fas 5: `Info.plist` för behörighet | ScreenCaptureKit (ingen Info.plist-nyckel för skärm, men `NSMicrophoneUsageDescription`/`NSAudioCaptureUsageDescription`), mikrofon via `captureMicrophone` på macOS 15+ | Så fungerar behörigheterna på riktigt. Systemljud + mikrofon mixas till en M4A. |
| Entitlements "vid behov" | Från start: `app-sandbox`, `files.user-selected.read-write`, `network.client`, `device.audio-input` | Utan `network.client` kan modellerna inte laddas ner i sandlådan. |
| — | **CI + releaser**: GitHub Actions bygger, testar och publicerar `.dmg`; förberett för Developer ID-signering och notarisering via secrets | Färdig app att ladda ner för alla Mac-användare. |

## Teknisk stack

- Swift 5-läge, SwiftUI, Observation (`@Observable`), SwiftData. Minsta macOS: 14 Sonoma. Apple Silicon.
- WhisperKit + SpeakerKit (Argmax, MIT), AVFoundation/AVKit, ScreenCaptureKit.
- `TranskriberaCore`: plattformsoberoende Swift-paket med export, sök och tidsformat, med XCTest.

## Arkitektur

```
TranskriberaApp ─┬─ AppState (vald transkribering, filväljare)
                 ├─ TranscriptionQueue ── TranscriberService ── WhisperKit / SpeakerKit
                 │        │                      └── AudioLoader (AVAssetReader → [Float] 16 kHz)
                 │        └── SwiftData: Transcript ─< TranscriptSegment
                 └─ MeetingRecorder (ScreenCaptureKit → M4A) ──> TranscriptionQueue
Views: ContentView (NavigationSplitView)
       ├─ SidebarView (grupperad lista, filter, radera, transkribera igen)
       ├─ NewTranscriptionView (drop-zon, snabbinställningar, mötesinspelning)
       └─ TranscriptDetailView (AVPlayerView, segmentlista, sök, redigering, export)
```

## Faser och status

### Fas 1 – Grund och gränssnitt ✅
- XcodeGen-projekt, entitlements, ikon.
- `NavigationSplitView` med sidopanel (Idag / Senaste veckan / Tidigare) och detaljvy.
- Drag & drop (`dropDestination`) och filväljare (`fileImporter`, ⌘O).

### Fas 2 – WhisperKit ✅
- `TranscriberService`: laddar ner modell med progress, laddar/prewarmar, transkriberar med VAD-chunkning.
- Tillstånd: idle, laddar ner, laddar modell, förbereder ljud, transkriberar (med %), identifierar talare, fel.
- Modell- och språkval på startsidan och i Inställningar (⌘,); hantera nedladdade modeller.

### Fas 3 – Detaljvy ✅
- AVPlayerView överst (video eller kompakt ljudspelare).
- Segment med tidsstämpel, talare och text; klick = hoppa och spela.
- Aktivt segment och ord markeras; "följ uppspelning".
- Redigeringsläge för texten; byt namn på titel och talare.

### Fas 4 – Sök och export ✅
- `.searchable` med markering, antal träffar och "visa bara träffar".
- Export: .txt, .md, .srt, .vtt, .json. Långa undertexter delas på ordgränser.
- Kopiera hela texten, ett segment eller ett segment med tidsstämpel.

### Fas 5 – Mötesinspelning ✅ (första version)
- ScreenCaptureKit spelar in systemljud (exkl. appens eget ljud), mikrofon på macOS 15+.
- Stoppa → M4A sparas → transkriberas automatiskt.

## Nästa steg (förslag)

1. Testa på riktig Mac: behörighetsflöden för inspelning, långa filer (> 1 h) och minnesanvändning.
2. Live-transkribering under inspelning (WhisperKit streaming).
3. Developer ID-signering och notarisering (lägg in secrets, se README).
4. Sparkle för automatiska uppdateringar.
5. Stöd för Intel-Mac (universal build) om det behövs.
