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
| Release-bygget för 0.5.2 stoppades av att `hdiutil attach` misslyckades tyst direkt efter att .dmg:n skapats | CI | Monteringen försöker igen upp till fem gånger och visar felet | `smoke-test.sh`, `upgrade-test.sh` |
| Byggen avbröts efter lång väntan i kö innan något steg körts | CI | Körs om automatiskt (högst två gånger) | `rerun-cancelled.yml` |
| KB-Whisper hoppade över hela partier av en intervju utan att det syntes, och en trasig specialtoken ("|mospeech|>") läckte ut i texten | 0.5.0 | Efter transkriberingen jämförs var det låter som tal med var det finns text; luckor på minst 2 s transkriberas om. Enhetstester för luckdetektionen och för trasiga specialtokens | `SpeechCoverageTests`, `TextCleaningTests` |
| Med Pianissimo hamnade sista ordet i en replik hos nästa talare: skiljetecknet förlängde ordet in i nästa tur, och talarbyten lades mitt i meningar | 0.5.0 | Enhetstester med fallen från intervjun: ordets slut styrs inte av skiljetecken, och korta talarbitar utan meningsslut eller paus följer grannen | `TokenWordsTests`, `SpeakerAssignmentTests` |
| Förloppet stod på 0 % och ingen text visades under hela transkriberingen med Whisper-modellerna: WhisperKit skickar inte vidare förloppsfunktionen när ljudet är längre än 30 s | 0.5.1 | En riktig Whisper-modell (tiny) transkriberar 1,5 minuter talsyntes; förloppet ska röra sig mellan 0 och 100 %, aldrig gå bakåt och nå 100 %, och löpande text ska komma. Utan procent visas ett obestämt förlopp i stället för en nolla | `WhisperProgressTests` |
| Transkriberingen med Whisper-modellerna kunde stå still (t.ex. på 46 %) medan datorn gick för fullt: med ordlista slutade WhisperKits regler för tidsstämplar gälla, och ett fönster som slutade på `<\|0.00\|>` avkodades om i all evighet | 0.5.2 | Enhetstester: reglerna för tidsstämplar gäller även med ordlista, och fönsterloopen flyttar alltid fram (står den still hoppar den över fönstret). En riktig modell (tiny) transkriberar 1,5 minuter tal med ordlista och ska bli klar inom 10 minuter. Två tester larmar om WhisperKit själv rättar felen | `WhisperLoopGuardTests` |
| Med Pianissimo saknades mellanslag ("typ100") eftersom en ensam ordgräns-token hoppades över, och en mening som fortsatte i nästa segment delades mellan två talare | 0.5.1 | Enhetstester: en ensam ordgräns börjar ett nytt ord, och korta talarbitar följer grannen även över segmentgränser | `TokenWordsTests`, `SpeakerAssignmentTests` |
| Ett kort svar som talaridentifieringen inte gett någon egen tur hamnade hos den som frågade: ord mer än 0,5 s från alla turer fick föregående talare | 0.5.2 | Enhetstest: ett svar i en lucka mellan turer får närmaste tur | `SpeakerAssignmentTests` |
| Korta svar direkt efter en fråga hamnade hos den som frågade, med samma fel oavsett taligenkänningsmodell (orsak i community-1: tal under 1 s fick inget röstavtryck och därmed ingen egen tur; gränsen sänkt till 0,3 s) | 0.5.2 | Den nya talaridentifieringen körs på riktigt på ett påhittat samtal med två röster från talsyntesen och korta svar ("Varje dag."); varje replik ska hamna hos rätt talare. Dagens talaridentifiering körs på samma samtal och resultatet skrivs i loggen | `CommunityDiarizerTests` |
| Repliker där talartilldelningen är osäker syntes inte, så felen i korta svar upptäcktes först vid läsning | 0.5.2 | Enhetstester: ⚠ vid talarbyte mitt i ett segment, ord som flyttats av utjämningen, repliker utanför talarens turer och samtidigt tal, men inte vid rena turer. ⚠ sparas med orden, äldre sparade ord går att läsa, och ⚠ står i analysexporten | `SpeakerAssignmentTests`, `AnalysisExporterTests` |
| Roller (Intervjuare, Kund N) får aldrig anonymiseras bort | – | Enhetstest: alla roller som appen sätter räknas som anonyma etiketter | `SpeakerRolesTests` |
| Punkter under [Kommande] hamnade i den redan släppta 0.5.3 när en PR slogs ihop efter versionshöjningen (git lade in dem i avsnittet ovanför) | 0.5.3 | Varje bygge jämför avsnitten för släppta versioner med CHANGELOG.md vid versionens tagg och stoppar om de ändrats | `changelog.py released`, `test_release_checks.py` |
| Talartilldelningen blev fel på verkliga inspelningar fast det syntetiska testet var grönt, och orsaken (saknad tur, fel röst eller förskjutna ordtider) gick inte att avgöra utan ljudet | – | Enhetstest: felsökningsfilen med talarturer och ordtider innehåller inte ett enda ord ur samtalet, så den går att skicka vidare | `SpeakerDiagnosticsTests` |
| Möten med flera intervjuare fick ingen roll för den andra intervjuaren, så den räknades som kund | – | Enhetstester: flera intervjuare numreras, roller kan ändras i efterhand och alla rollnamn är undantagna från anonymiseringen | `SpeakerRolesTests` |
| Ett valt antal talare kunde försvinna när inställningen bytte format | – | Enhetstester: varje val överlever att sparas, och den gamla inställningen ger samma val | `SpeakerCountTests` |
| Talare som döpts om till "Intervjuare" eller "Kund 1" anonymiserades som personnamn ("[PERSON 1]"), och rollordet doldes i texten | 0.5.2 | Enhetstest: roller och "Talare N" lämnas orörda av anonymiseringen | `AnonymizerTests` |
| Pianissimo kan inte få ordlistan som ledtråd, så namn i den stavades fel ("Fotnox") | 0.5.1 | Enhetstester: namn i ordlistan som hörts nästan rätt rättas, men vanliga ord, meningsinledningar, fackord med gemen och tvetydiga fall lämnas orörda | `VocabularyCorrectionTests` |
| KB Large ordagrann visades i modellväljaren fast konverteringen hade misslyckats, så nedladdningen skulle ge fel | före 0.5.0 | Varje modell i väljaren (`WhisperModel.offered`) ska gå att ladda ner: zip-filen i sin release, WhisperKit-varianten på Hugging Face | `check-models.sh` |
| KB-Whisper-modellen blev trunkerad vid uppladdning | modeller | Varje zip testas med `unzip -t` före och efter uppladdning; trasiga byggs om | `kb-whisper-models.yml` |
| Radbrutna punkter i CHANGELOG.md blev lösa stycken i uppdateringsdialogen | 0.5.0 | Test att varje punkt blir en hel listpunkt, även för den aktuella CHANGELOG.md | `test_release_checks.py` |
| Byggnumret måste öka, annars hittar Sparkle inte versionen | – | Byggnumret jämförs med appcasten | `appcast.py check` |

## Skydd mot det som inte har hänt än

| Risk | Kontroll | Var |
| --- | --- | --- |
| En ny version kan inte öppna databasen från förra versionen (ändrad modell utan migrering) och kraschar eller tappar transkriberingar | Uppgraderingstest: förra släppta versionen installeras och får en transkribering och inställningar, uppdaterar sig själv med Sparkle till det nya bygget, och det nya bygget ska ha kvar allt | `upgrade-test.sh`, `upgrade_store.py` |
| En ny version flyttar eller tar bort nedladdade modeller, så att användaren måste ladda ner flera GB igen | Uppgraderingstestet lägger modellfiler för KB-Whisper, OpenAI och Pianissimo där appen letar efter dem, och de ska finnas kvar efter uppdateringen | `upgrade-test.sh` |
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
