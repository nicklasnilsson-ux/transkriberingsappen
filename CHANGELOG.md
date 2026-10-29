# Ändringslogg

Allt som ändras för användaren, version för version. Avsnittet för en version blir
releasens text på GitHub och i uppdateringsdialogen. CI stoppar en ny version som saknar
avsnitt här (se docs/RELEASE.md). Skriv för användaren, inte för utvecklaren.

## [Kommande]

## [0.5.4] – 2026-10-29

### Nytt
- Experiment: ny talaridentifiering (pyannote community-1) under Inställningar →
  Transkribering. Den körs lokalt, som den nuvarande, och kräver macOS 15. Slå på den
  och transkribera samma fil två gånger för att jämföra vem som får vilka repliker.
- Antal talare kan nu vara ett spann, t.ex. 2–4, när du inte vet hur många som är med.
  Automatiskt betyder nu minst 2 talare med den nya talaridentifieringen.
- Ange vem som är intervjuaren: efter en transkribering med talare frågar appen vem
  av talarna du är. Då heter talarna Intervjuare, Kund 1, Kund 2 och så vidare. Det
  går också att välja under Talare i verktygsfältet eller genom att högerklicka.
- ⚠ bredvid talaren där det är osäkert vem som sa repliken, till exempel vid ett
  talarbyte utan paus eller när två pratar samtidigt. Markeringen följer med i
  Exportera för analys, så att ett korrekturpass vet var det ska titta.

## [0.5.3] – 2026-10-29

### Nytt
- Två experiment under Inställningar → Transkribering för att jämföra kvaliteten:
  noggrannare skarvar för Pianissimo och utjämnad volym, som förstärker svaga röster.
  Det som användes står efter modellens namn i transkriberingen.

### Rättat
- En transkribering med Whisper-modellerna (t.ex. KB-Whisper) kunde stanna mitt i, till
  exempel på 46 %, medan datorn fortsatte att arbeta för fullt: modellen kunde fastna
  och tolka samma bit av ljudet om och om igen, särskilt med ord i ordlistan. Nu går den
  alltid vidare, och tal som hoppats över fångas av kontrollen efteråt.
- Korta svar som "Varje dag" kunde hamna hos den som ställde frågan när
  talaridentifieringen missat dem. Nu går de till den talare som hörs närmast i tid.
- Döper du om en talare till "Intervjuare" eller "Kund 1" byts namnet inte längre ut
  mot "[PERSON 1]" när texten anonymiseras.

## [0.5.2] – 2026-10-29

### Nytt
- Ordlistan gäller nu också Pianissimo: namn som modellen hört nästan rätt, t.ex.
  "Fotnox" i stället för "Fortnox", rättas i efterhand. Det gäller alla modeller.

### Rättat
- Förloppet stod på 0 % under hela transkriberingen med KB-Whisper och de andra
  Whisper-modellerna. Nu rör det sig, och texten som hittats syns medan du väntar.
- När appen inte kan räkna ut hur långt den har kommit rör sig stapeln i stället för att
  stå still på noll.
- Förloppet visar vilket steg som pågår, till exempel "Steg 3 av 4", så att det syns
  varför stapeln börjar om.
- Pianissimo tappade ibland mellanslag mellan ord, t.ex. "typ100" och "villändra".
- En mening som fortsätter i nästa stycke delas inte längre mellan två talare.

## [0.5.1] – 2026-10-29

### Nytt
- KB-Whisper Large finns nu också i en mer ordagrann variant, för intervjuer där du vill
  kunna citera exakt.

### Rättat
- Partier med tal som KB-Whisper hoppat över transkriberas om automatiskt, så att
  färre delar av samtalet saknas.
- Trasiga interna markeringar som "|nospeech|>" syns inte längre i texten.
- Sista eller första ordet i en replik hamnar inte längre hos fel talare, särskilt med
  Pianissimo. Talarbyten läggs vid meningsslut eller pauser.
- Namnet Joy döljs vid anonymisering.

## [0.5.0] – 2026-10-28

### Nytt
- Talare sätts per ord, så att ett kort svar direkt efter en fråga hamnar hos rätt talare.
  Du kan ange antal talare om du vet det.
- Ordlista med namn och fackord som hjälper modellen att stava rätt.
- KB-Whisper Medium finns i en mer ordagrann variant som stryker mindre.
- Pianissimo (KlangAI) som modellval för svenska.

### Förbättrat
- Färre tappade meningar när någon talar svagt.
- Anonymiseringen döljer personer och platser men inte organisationer eller vanliga ord,
  och du kan ange ord som alltid eller aldrig ska döljas.
- Appen säkerhetskopierar dina transkriberingar innan en ny version öppnar dem, och kraschar
  inte längre om databasen inte går att läsa. Då sparas den undan och du får veta var.

## [0.4.2] – 2026-10-28

### Rättat
- Appen startar igen. 0.4.0 och 0.4.1 stängdes direkt vid start på grund av hur
  uppdateringsfunktionen var signerad.

## [0.4.1] – 2026-10-28

### Rättat
- Försök att rätta kraschen vid start i 0.4.0 (räckte inte, se 0.4.2).
- Appen visar rätt versionsnummer i stället för 1.0.

## [0.4.0] – 2026-10-28

### Nytt
- Automatiska uppdateringar, med betaversioner för den som vill.
- Transkriberingen visas som stycken per talare, med en växel till en rad per segment.

## [0.3.0] – 2026-10-28

### Nytt
- KB-Whisper, KBLab:s svenska modeller, först i modellväljaren. KB Small är standard.
- Modellväljaren visar felfrekvens och storlek för varje modell.

## [0.2.0] – 2026-10-28

### Nytt
- Anonymisering av namn, personnummer och andra känsliga uppgifter vid visning, kopiering
  och export. Originaltexten sparas.
- *Exportera för analys*: en Markdown-fil per session med talare och tidskoder.

### Förbättrat
- Tydligare texter och hjälptexter i hela appen.

## [0.1.0] – 2026-10-28

### Nytt
- Första versionen: lokal transkribering med Whisper, talaridentifiering, spelare med
  klickbara tidsstämplar, sök, redigering, mötesinspelning och export till TXT, Markdown,
  SRT, VTT och JSON.
