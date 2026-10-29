# Fel vi haft och kontrollerna som stoppar dem

Princip: varje fel som når en användare (eller nästan gör det) blir en automatisk kontroll
i CI som stoppar releasen, så att samma fel inte kan komma tillbaka. Lägg till en rad här
och en kontroll i samma PR som rättar felet.

Allt nedan körs i workflowen `Bygg` på varje PR och varje release. En release skapas
först som **utkast**. Den blir synlig och hamnar i appcasten (så att appar uppdaterar sig)
först när alla kontroller är gröna på exakt de filer som laddades upp.

| Fel | Version | Kontroll | Var |
| --- | --- | --- | --- |
| Appen visade version 1.0 (1), så Sparkle kunde inte jämföra versioner | ≤ 0.4.0 | Version och byggnummer i appens Info.plist ska stämma med releasen | `smoke-test.sh` |
| Sparkle hade ett annat Team ID än appen, macOS vägrade ladda ramverket och appen stängdes vid start | 0.4.0 | Med härdad runtime eller library validation ska all kod i appen ha appens Team ID | `smoke-test.sh` |
| Ad hoc-signering + härdad runtime: library validation utan Team ID, Sparkle laddades inte | 0.4.1 | Ingen kod får vara ad hoc-signerad med härdad runtime | `smoke-test.sh` |
| Starttestet i CI missade felen ovan eftersom GitHubs macOS-maskiner har SIP avstängt | 0.4.0–0.4.1 | Reglerna kontrolleras statiskt (signaturflaggor, Team ID, länkade ramverk) i stället för att lita på att appen startar | `smoke-test.sh` |
| Appen startades aldrig innan release | ≤ 0.4.0 | Appen startas från .dmg:n och ska leva i 15 sekunder utan kraschrapport | `smoke-test.sh` |
| Det som laddades upp testades inte, bara det som byggdes | ≤ 0.4.2 | Releasen skapas som utkast; de uppladdade filerna laddas ner, jämförs (SHA-256) och röktestas innan releasen publiceras. Grinden körs på varje PR också (med ett tillfälligt utkast som tas bort), så att den är testad innan den behövs | `build.yml`, *Release-grind* |
| En release nådde användarna innan den var kontrollerad | ≤ 0.4.2 | Appcasten uppdateras först efter release-grinden | `build.yml` |
| Byggen avbröts efter lång väntan i kö innan något steg körts | CI | Körs om automatiskt (högst två gånger) | `rerun-cancelled.yml` |
| KB-Whisper hoppade över hela partier av en intervju utan att det syntes, och en trasig specialtoken ("|mospeech|>") läckte ut i texten | 0.5.0 | Efter transkriberingen jämförs var det låter som tal med var det finns text; luckor på minst 2 s transkriberas om. Enhetstester för luckdetektionen och för trasiga specialtokens | `SpeechCoverageTests`, `TextCleaningTests` |
| Med Pianissimo hamnade sista ordet i en replik hos nästa talare: skiljetecknet förlängde ordet in i nästa tur, och talarbyten lades mitt i meningar | 0.5.0 | Enhetstester med fallen från intervjun: ordets slut styrs inte av skiljetecken, och korta talarbitar utan meningsslut eller paus följer grannen | `TokenWordsTests`, `SpeakerAssignmentTests` |
| Förloppet stod på 0 % och ingen text visades under hela transkriberingen med Whisper-modellerna: WhisperKit skickar inte vidare förloppsfunktionen när ljudet är längre än 30 s | 0.5.1 | En riktig Whisper-modell (tiny) transkriberar 1,5 minuter talsyntes; förloppet ska röra sig mellan 0 och 100 %, aldrig gå bakåt och nå 100 %, och löpande text ska komma. Utan procent visas ett obestämt förlopp i stället för en nolla | `WhisperProgressTests` |
| Med Pianissimo saknades mellanslag ("typ100") eftersom en ensam ordgräns-token hoppades över, och en mening som fortsatte i nästa segment delades mellan två talare | 0.5.1 | Enhetstester: en ensam ordgräns börjar ett nytt ord, och korta talarbitar följer grannen även över segmentgränser | `TokenWordsTests`, `SpeakerAssignmentTests` |
| KB Large ordagrann visades i modellväljaren fast konverteringen hade misslyckats, så nedladdningen skulle ge fel | före 0.5.0 | Varje modell i väljaren (`WhisperModel.offered`) ska gå att ladda ner: zip-filen i sin release, WhisperKit-varianten på Hugging Face | `check-models.sh` |
| KB-Whisper-modellen blev trunkerad vid uppladdning | modeller | Varje zip testas med `unzip -t` före och efter uppladdning; trasiga byggs om | `kb-whisper-models.yml` |
| Radbrutna punkter i CHANGELOG.md blev lösa stycken i uppdateringsdialogen | 0.5.0 | Test att varje punkt blir en hel listpunkt, även för den aktuella CHANGELOG.md | `test_release_checks.py` |
| Byggnumret måste öka, annars hittar Sparkle inte versionen | – | Byggnumret jämförs med appcasten | `appcast.py check` |

## Skydd mot det som inte har hänt än

| Risk | Kontroll | Var |
| --- | --- | --- |
| En ny version kan inte öppna databasen från förra versionen (ändrad modell utan migrering) och kraschar eller tappar transkriberingar | Uppgraderingstest: förra släppta versionen installeras och får en transkribering och inställningar, uppdaterar sig själv med Sparkle till det nya bygget, och det nya bygget ska ha kvar allt | `upgrade-test.sh`, `upgrade_store.py` |
| Databasen går inte att öppna hos en användare | Appen kraschar inte: databasen flyttas till `Säkerhetskopior` och användaren får veta var | `Database.swift` |
| En migrering förstör data | Databasen kopieras till `Säkerhetskopior` första gången en ny version startar (de fem senaste sparas) | `Database.swift` |
| Uppdateringsflödet går sönder (signatur, appcast, installation i sandlådan) | Uppgraderingstestet går genom Sparkle på riktigt, med appcasten signerad med den riktiga nyckeln | `upgrade-test.sh` |
| Ett beroende byter version utan att vi märker det | Alla Swift-paket, även indirekta, är låsta i `Package.resolved`; bygget avbryts om låsfilen inte stämmer | `build-app.sh` |
| Info.plist saknar något som krävs (uppdateringsnyckel, flöde, behörighetstexter, lägsta macOS) | Kontrolleras i röktestet | `smoke-test.sh` |
| En ny version saknar beskrivning | Versionen måste ha ett avsnitt i `CHANGELOG.md`, redan i PR:en som höjer den | `changelog.py check` |

## Vad CI inte kan kontrollera

- **Gatekeeper för ad hoc-signerade appar.** En osignerad app avvisas alltid av Gatekeeper
  och öppnas första gången med högerklick → Öppna. Det försvinner när appen signeras med
  ett Developer ID; då kräver röktestet att Gatekeeper godkänner appen.
- **Mikrofon, datorljud och riktiga möten.** Behörighetsdialoger och inspelning går inte att
  testa på CI-maskinerna. Det ingår i checklistan i [RELEASE.md](RELEASE.md).
