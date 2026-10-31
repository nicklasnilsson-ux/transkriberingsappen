# Ändringslogg

Allt som ändras för användaren, version för version. Avsnittet för en version blir
releasens text på GitHub och i uppdateringsdialogen. CI stoppar en ny version som saknar
avsnitt här (se docs/RELEASE.md). Skriv för användaren, inte för utvecklaren.

## [Kommande]

### Nytt
- Exporten för analys börjar med ett avsnitt, "Om den här filen", som förklarar vad ⚠, platshållare som [PERSON 1] och rollerna Intervjuare och Kund betyder, och att en automatisk transkribering kan missa småord och ”eh”/”mm”, så att den som läser filen (t.ex. en AI) förstår den. Bara det som gäller filen tas med. Du kan stänga av det i exportdialogen.

## [0.6.1] – 2026-10-31

### Ändrat
- Testlabbet har en ny körlista. Första omgången visade att spärrarna, fönsterklippet och omkörningarna inte spelar någon roll, och att KB-Whisper inte skriver ut "eh" och "mm" alls (facit har ungefär 60 på 18 minuter). Nu provas en ledtråd med fyllnadsord, som lista och som löpande text, med och utan i luckkontrollen, plus Pianissimo som jämförelse. Vanliga transkriberingar påverkas inte.

## [0.6.0] – 2026-10-31

### Nytt
- Testlabb under Hjälp → Testlabb…, för att jämföra inställningar. Välj en inspelning så körs den med KB Large ordagrann och Pianissimo med ett antal olika inställningar efter varandra (t.ex. utan spärrarna som kastar text modellen är osäker på). Varje körning sparas som en textfil och en logg i en mapp. Vanliga transkriberingar påverkas inte; nya filer väntar i kön medan labbet kör.

### Ändrat
- Valet "Hitta fler luckor med Pianissimo" är borta. I en testintervju gav det 14,5 % ordfel mot 14,7 % utan, och två körningar med samma inställningar skiljer sig lika mycket, så det syns ingen vinst. Det krävde också en extra modell och längre tid.

## [0.5.9] – 2026-10-30

### Ändrat
- Inställningarna är städade. "Ny talaridentifiering (pyannote community-1)" är borta: Nemotron 3 är standard, och går det inte att använda den eller du valt ett fast antal talare används den vanliga talaridentifieringen. Nemotron 3 ligger nu bland talarinställningarna, volymutjämningen under "Ordträff", och val som inte gäller vald modell är gråade.
- "Hitta luckor med Pianissimo" heter nu "Hitta fler luckor med Pianissimo". Det lägger till Pianissimos luckor utöver kontrollen med ljudnivå i stället för att ersätta den, och fyller i saknade ord ett och ett i stället för hela meningar.

## [0.5.8] – 2026-10-30

### Nytt
- Experiment under Inställningar: "Hitta luckor med Pianissimo (KB-Whisper)". Pianissimo lyssnar igenom ljudet först och pekar ut var det finns tal som KB-Whisper missat. De ställena körs om, och saknas text ändå fylls den i från Pianissimo. Kräver att Pianissimo är nedladdad och tar lite längre tid. Det som användes står efter modellens namn.

### Ändrat
- Talaridentifieringen använder nu Nemotron 3 som standard när antal talare är automatiskt. Den hittade nästan alla korta kundsvar i en testintervju (99 % av orden hos rätt roll mot 95 % tidigare) och delar inte längre en ensam kund i två. Första gången laddas en modell på några hundra MB ner. Går det inte används den gamla vägen, och ett fast antal talare går också dit. Kan slås av under Inställningar → Experiment.

## [0.5.7] – 2026-10-30

### Nytt
- Experiment under Inställningar: "Talaridentifiering för korta svar (Nemotron 3)", NVIDIAs nyaste modell för korta repliker och snabba byten. Upp till åtta talare, körs lokalt och ersätter den vanliga talaridentifieringen när den är på. Det som användes står efter modellens namn.

### Ändrat
- I analysexporten märks bara den osäkra delen av ett stycke med ⚠, inte hela stycket. En kort kundreplik inuti en lång intervjuarreplik syns därmed för sig, och mycket färre ord flaggas.

## [0.5.6] – 2026-10-30

### Nytt
- Det går att ange flera intervjuare, till exempel när två från ert håll är med. De heter då
  Intervjuare 1 och Intervjuare 2, och kunderna Kund 1, Kund 2 och så vidare. Välj under
  Talare → Intervjuare.
- Under Talare finns nu "Visa talarturer i Finder (för felsökning)". Där sparas, för de
  20 senaste transkriberingarna, när talaridentifieringen tycker att varje talare hörs och
  hur orden delades mellan dem. Filerna innehåller bara tider och talarnummer, ingen text,
  så de går att skicka när talarna blir fel.

## [0.5.5] – 2026-10-29

### Nytt
- Volymen jämnas nu ut som standard för KB-Whisper, så att svaga röster hörs lika bra
  som starka. I två intervjuer gav det 2–3 procentenheter färre ordfel jämfört med
  Klang. Pianissimo påverkas inte, eftersom den jämnar ut volymen själv. Du kan stänga
  av det under Inställningar → Transkribering → Experiment.

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
