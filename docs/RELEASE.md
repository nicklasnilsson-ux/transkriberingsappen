# Releaser och uppdateringar

Transkribera uppdaterar sig själv med [Sparkle](https://sparkle-project.org). Appen läser
appcasten på branchen [`appcast`](https://github.com/nicklasnilsson-ux/transkriberingsappen/tree/appcast)
en gång om dagen, laddar ner nya versioner i bakgrunden och installerar dem när appen avslutas.
Allt det byggs och publiceras av workflowen `Bygg` (`.github/workflows/build.yml`).

## Kanaler

| Kanal | Vem får den | Hur den släpps |
| --- | --- | --- |
| **Stabil** | Alla | Automatiskt när `main` får en ny `MARKETING_VERSION` i `project.yml` |
| **Beta** | De som valt *Inställningar → Uppdateringar → Få betaversioner* | Manuellt: *Actions → Bygg → Run workflow*, välj branch och `beta` |

En beta får versionen `X.Y.Z-beta.N` och byggnumret `(nästa byggnummer − 1).N`, till exempel
`3.42` när nästa stabila bygge är `4`. Så när den stabila versionen släpps ersätter den betan
hos betatestarna, och flera betor i rad går alltid uppåt. Betor syns som *pre-release* på GitHub.

## Processen

1. **Gör ändringarna i en PR.** CI kör enhetstesterna, testerna för releaseskripten, bygger
   appen och kör alla kontroller i [KONTROLLER.md](KONTROLLER.md): röktest av `.dmg`:n
   (version, signaturer, ramverk, start) och uppgraderingstest från förra versionen (Sparkle,
   data och inställningar kvar). Mergea bara när allt är grönt.
2. **Höj versionen i samma PR eller en egen**: `MARKETING_VERSION` (t.ex. `0.5.0`) och
   `CURRENT_PROJECT_VERSION` (heltal, alltid +1) i `project.yml`, och byt rubriken
   `## [Kommande]` i `CHANGELOG.md` till `## [0.5.0] – ÅÅÅÅ-MM-DD`. CI stoppar en ny version
   utan avsnitt i CHANGELOG.md och ett byggnummer som inte är högre än appcastens.
3. **Släpp en beta** från PR-branchen: *Actions → Bygg → Run workflow → Use workflow from:
   branchen → beta*. Du och betatestarna får den inom ett dygn, eller direkt med
   *Transkribera → Sök efter uppdateringar…*.
4. **Testa betan på en riktig Mac** med checklistan nedan. Hittar du fel: fixa i PR:en och
   släpp en ny beta.
5. **Mergea PR:en.** Bygget på `main` skapar releasen som utkast, laddar ner de uppladdade
   filerna och kör röktestet på dem (*release-grinden*). Först när den är grön publiceras
   releasen och läggs in i appcasten, så att alla får den automatiskt. Stoppas den syns
   ingenting för användarna; rätta felet och kör om (utkastet ersätts).

Liten rättning som inte behöver beta: hoppa över steg 3–4, men gör ändå röktestet på
din egen Mac efter releasen.

## Checklista före release

CI sköter det här, men titta att det stämmer:

- [ ] Alla steg i `Bygg` är gröna, även *Uppgraderingstest* och *Release-grind*.
- [ ] `CHANGELOG.md` beskriver ändringarna för användaren.
- [ ] Ändras `Transcript` eller `TranscriptSegment`: ny schemaversion och migrering enligt
      kommentaren i `Transkribera/Models/Database.swift`.
- [ ] Nya beroenden: `make update-packages` och committa `Package.resolved`.
- [ ] Nytt fel hittat: en rad i [KONTROLLER.md](KONTROLLER.md) och en kontroll som stoppar det.

## Checklista på riktig Mac (cirka 10 minuter)

Gör den på betan innan den blir stabil. Börja från den senaste stabila versionen, så att
själva uppdateringen också testas.

- [ ] *Sök efter uppdateringar…* hittar den nya versionen, den installeras och appen startar om.
- [ ] *Om Transkribera* visar rätt version. Tidigare transkriberingar och inställningar finns kvar.
- [ ] Importera en kort ljudfil på svenska med KB-Whisper: texten blir rimlig.
- [ ] Anonymiseringen maskerar ett namn och ett personnummer.
- [ ] Spela in ett kort möte (datorljud + mikrofon) och transkribera det.
- [ ] Exportera (SRT/TXT) och *Exportera för analys* ger filer som går att öppna.
- [ ] Det som PR:en ändrade fungerar som tänkt.

## Beroenden

Alla Swift-paket, även de som andra paket drar in, är låsta i `Package.resolved`.
`scripts/build-app.sh` lägger låsfilen i Xcode-projektet och bygger med
`-disableAutomaticPackageResolution`, så bygget avbryts i stället för att tyst byta version.
Uppdatera med `make update-packages` (löser upp de senaste versionerna inom ramarna i
`project.yml`) och committa låsfilen i en egen PR, så att röktest och uppgraderingstest
körs på de nya versionerna. Dependabot håller GitHub Actions och Python-paketen för
releaseskripten (`scripts/requirements.txt`) uppdaterade.

## Databasen

Transkriberingarna ligger i en SwiftData-databas i appens sandlåda
(`~/Library/Containers/se.nicklasnilsson.transkribera/Data/Library/Application Support/Transkribera`).
Schemat är versionerat (`SchemaV1` och `TranskriberaMigrationPlan` i `Database.swift`).
Första gången en ny version startar kopieras databasen till `Säkerhetskopior`; går den inte
att öppna flyttas den dit och appen startar med en tom lista och ett meddelande, i stället
för att krascha.

## Engångsinställning: signeringsnyckeln

Uppdateringarna signeras med en EdDSA-nyckel (Ed25519). Den publika nyckeln står i
`project.yml` (`SUPublicEDKey`) och byggs in i appen. Den privata ligger som repo-secret
`SPARKLE_PRIVATE_KEY` (base64, samma format som Sparkles `generate_keys -x`).

Saknas secreten släpps versionen ändå på GitHub, men appcasten uppdateras inte och CI visar
en varning, så ingen får den automatiskt. Kör då workflowen igen när secreten finns.

Tappas den privata nyckeln bort kan installerade appar inte längre uppdateras automatiskt
förrän appen signeras med ett Developer ID (Sparkle tillåter byte av antingen EdDSA-nyckel
eller kodsignering, inte båda samtidigt). Spara den därför även i en lösenordshanterare.

## Apple-signering senare

Appen är ad hoc-signerad i dag, vilket Sparkle stöder när uppdateringarna är EdDSA-signerade.
När secrets för Developer ID läggs in (se README) signerar `scripts/sign-and-notarize.sh`
Sparkles delar i rätt ordning och notariserar. Gör bytet i en egen release och behåll samma
EdDSA-nyckel, så går uppdateringen från ad hoc till Developer ID igenom.

## Tekniska detaljer

- `scripts/smoke-test.sh` och `scripts/upgrade-test.sh` är kontrollerna, se [KONTROLLER.md](KONTROLLER.md).
- `scripts/codesign-app.sh` signerar appen inifrån och ut (Sparkles delar först). Härdad
  runtime används bara med Developer ID: med ad hoc-signering vägrar macOS då ladda Sparkle
  (0.4.0 och 0.4.1 startade inte av det skälet). Röktestet stoppar ett sådant bygge.
- `scripts/make-dmg.sh` gör både `.dmg` (för nya användare) och `.zip` (för Sparkle).
- `scripts/appcast.py` signerar zip-filen och skriver appcasten. Tester: `scripts/test_appcast.py`.
- `scripts/publish-appcast.sh` committar appcasten till branchen `appcast`.
- Appen är sandlådad, så Sparkles installationstjänst är påslagen (`SUEnableInstallerLauncherService`)
  med motsvarande `mach-lookup`-undantag i entitlements.
