# Ändringslogg

Allt som ändras för användaren, version för version. Avsnittet för en version blir
releasens text på GitHub och i uppdateringsdialogen. CI stoppar en ny version som saknar
avsnitt här (se docs/RELEASE.md). Skriv för användaren, inte för utvecklaren.

## [Kommande]

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
