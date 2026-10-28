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

1. **Gör ändringarna i en PR.** CI kör enhetstesterna (`TranskriberaCore`), testerna för
   releaseskripten, bygger hela appen och röktestar `.dmg`:n (`scripts/smoke-test.sh`: rätt
   version, giltig signatur och att appen startar). Mergea bara när allt är grönt.
2. **Höj versionen i samma PR eller en egen**: `MARKETING_VERSION` (t.ex. `0.5.0`) och
   `CURRENT_PROJECT_VERSION` (heltal, alltid +1) i `project.yml`. Byggnumret är det Sparkle
   jämför; CI stoppar releasen om det inte är högre än det som redan finns i appcasten.
3. **Släpp en beta** från PR-branchen: *Actions → Bygg → Run workflow → Use workflow from:
   branchen → beta*. Du och betatestarna får den inom ett dygn, eller direkt med
   *Transkribera → Sök efter uppdateringar…*.
4. **Testa betan på en riktig Mac** med checklistan nedan. Hittar du fel: fixa i PR:en och
   släpp en ny beta.
5. **Mergea PR:en.** Bygget på `main` skapar den stabila releasen och lägger in den i appcasten.
   Alla får den automatiskt.

Liten rättning som inte behöver beta: hoppa över steg 3–4, men gör ändå röktestet på
din egen Mac efter releasen.

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

- `scripts/codesign-app.sh` signerar appen inifrån och ut (Sparkles delar först). Härdad
  runtime används bara med Developer ID: med ad hoc-signering vägrar macOS då ladda Sparkle
  (0.4.0 och 0.4.1 startade inte av det skälet). Röktestet stoppar ett sådant bygge.
- `scripts/make-dmg.sh` gör både `.dmg` (för nya användare) och `.zip` (för Sparkle).
- `scripts/appcast.py` signerar zip-filen och skriver appcasten. Tester: `scripts/test_appcast.py`.
- `scripts/publish-appcast.sh` committar appcasten till branchen `appcast`.
- Appen är sandlådad, så Sparkles installationstjänst är påslagen (`SUEnableInstallerLauncherService`)
  med motsvarande `mach-lookup`-undantag i entitlements.
