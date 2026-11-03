# Ändringslogg

Allt som ändras för användaren, version för version. Avsnittet för en version blir
releasens text på GitHub och i uppdateringsdialogen. CI stoppar en ny version som saknar
avsnitt här (se docs/RELEASE.md). Skriv för användaren, inte för utvecklaren.

## [Kommande]

### Ändrat
- Frågan "Vem av talarna är du?" ligger i en tonad ruta. När du har valt visas "Klart. Talare 1 är intervjuare." med Ångra, som återställer talarna exakt som de var.

### Ändrat
- Transkribera igen ligger nu inne i rutan med modell, språk och talare, tillsammans med Återställ. Ändrade val kastas om man stänger rutan utan att transkribera igen. Klar visas med en grön bock, och en äldre version märks även i titelbaren.

### Ändrat
- Ny uppställning av fönstret: Fil/Mötesinspelning ligger överst i sidopanelen. Titelbaren har alltid Sök i texten (⌘F), Redigera och en ⋯-meny med verktygen. Spelaren ligger fast under titelbaren, och version, modell, verktygsrad och text skrollar tillsammans. Titelkortet fälls inte längre ihop. Exportera är en svart knapp. Namnet på transkriberingen byts i titelbaren.

### Ändrat
- Ny, vitare och stramare färgpalett i hela appen (ljust, mörkt och Öka kontrast), i stället för systemets bakgrunder. Accentfärgen är densamma. Stoppa inspelning är nu en neutral svart knapp, Starta inspelning behåller accentfärgen.

## [0.8.1] – 2026-11-03

### Ändrat
- Modell, språk och antal talare ovanför titelkortet är nu en enda knapp, till exempel "KB Large ordagrann · Svenska · 3 talare". De tre knapparna öppnade förut samma ruta. Klicka på knappen för att ändra valen till nästa omtagning.

### Rättat
- Datum och tid på andra raden i titelkortet visade alltid när filen först transkriberades, även när en annan version var vald. Nu visar raden när den version du ser blev klar. Versionsmärket säger bara "Version 3 av 3", eftersom klockslaget redan står i datumet.

## [0.8.0] – 2026-11-02

### Nytt
- Tidigare versioner av texten. "Transkribera igen" skriver inte längre över texten: den förra versionen sparas, med dina rättningar och talarnamn. Appen behåller de 4 senaste versionerna per transkribering, och äldre raderas.
- Versionsvalet ligger i titelkortet, till exempel "Version 2 av 4 · 14:32", och syns först när det finns fler än en version. En äldre version går att läsa, rätta, söka i, kopiera och exportera som vanligt, och en remsa under titelkortet säger att du tittar på en äldre version. När titelkortet är hopfällt syns bara märket "Äldre version" när du står i en äldre.
- Dialogen före "Transkribera igen" förklarar vad som händer: den här versionen sparas, du kan byta tillbaka med Version, och de 4 senaste behålls. Har du redan 4 versioner står det vilken som raderas (den äldsta, först när den nya är klar), och dialogen går då inte att stänga av. Annars finns "Visa inte den här rutan igen", som du slår på igen under Inställningar › Transkribering.

### Ändrat
- Ny appikon: en ljudvåg som blir textrader, på enfärgad indigo.
- Appens indigo används nu genom hela appen (knappar, markeringar, aktiv text), i både ljust och mörkt läge. Tidigare visades systemets blå eftersom accentfärgen inte var kopplad. Märket för svenska modeller följer samma färg.
- Testlabbet finns inte längre i Hjälp-menyn, eftersom det är ett verktyg för utveckling och inte för vanlig användning. Det öppnas fortfarande med genvägen ⌥⇧⌘T. Inget annat påverkas.
- Databasen får en ny version (schema 2) med plats för de sparade versionerna. Befintliga transkriberingar påverkas inte; de får en version tills du transkriberar om dem. En säkerhetskopia av databasen tas som vanligt när den nya versionen startas första gången.

### Rättat
- Avbryts eller misslyckas "Transkribera igen" längre fram står nu modellen som texten faktiskt gjordes med kvar (den byttes tidigare redan när körningen startade).
- Filer du släpper eller öppnar medan en mötesinspelning pågår läggs i kön och transkriberas först när inspelningen är sparad, så att inspelningen inte störs. Vyn byter inte längre till filen, så knappen Stoppa och transkribera finns kvar. På inspelningssidan står hur många filer som väntar.

## [0.7.13] – 2026-11-02

### Ändrat
- Sök i texten fungerar som ⌘F i en webbläsare. Hela texten visas, sökfältet visar till exempel "3 av 12" och du stegar mellan träffarna med pilarna, Retur eller ⌘G (⇧⌘G bakåt). Texten skrollar till träffen, som är orange; övriga träffar är gula. "Visa bara träffar" är borttaget.
- Det hopfällda titelkortet ligger kloss mot överkanten med raka hörn upptill, så att texten inte syns ovanför det.

### Rättat
- Sökfältet i det hopfällda titelkortet tappade fokus efter ett par bokstäver och sidan hoppade till början.

## [0.7.12] – 2026-11-02

### Ändrat
- Sökfältet följer med när titelkortet är hopfällt. Klickar du på Sök i texten medan du skrollar öppnas fältet direkt i den hopfällda raden, utan att sidan hoppar till början.
- Med liten bild eller bara ljud ligger spelkontrollerna staplade bredvid bilden i det hopfällda titelkortet. Då får texten om redigeringen plats.
- Det står nu "Redigerar anonymiserad text" (eller "Redigerar originaltexten") i stället för "Rättar …".

## [0.7.11] – 2026-11-02

### Ändrat
- När titelkortet är hopfällt ligger ljud och video längst till vänster, med titeln, Sök i texten och Redigera efter. Med mellanstor och stor bild ligger spelkontrollerna längst ned under knapparna.

## [0.7.10] – 2026-11-02

### Ändrat
- Titelkortet har fått en ny uppställning. Titeln står till vänster och status, datum och längd till höger. Under den ligger Talare, Anonymisera och Stycken/Rader, och till höger Kopiera text och Exportera. Under avdelaren ligger Sök i texten och Redigera.
- När titelkortet är hopfällt visas titeln med Sök i texten och Redigera till vänster och spelaren till höger. Anonymisera, Talare, Kopiera och Exportera finns bara i det utfällda titelkortet.
- Anonymisera och Klar är fyllda med accentfärgen när de är på, så att det syns vilket läge du är i. Texten "Rättar anonymiserad text" står direkt efter Klar.
- Märket med intervjuaren efter titeln är borttaget. Intervjuaren väljs under Talare.

## [0.7.9] – 2026-11-02

### Rättat
- Texten hoppar inte längre när du växlar mellan visning och redigering. Fältet har samma radavstånd som texten du läser, både i stycken och rader. Ett helt stycke redigeras i ett enda fält med samma radbrytning som när du läser, och ändringen sparas på rätt ställe i transkriberingen. Stycket du läser står kvar på samma plats i fönstret när du växlar läge.

## [0.7.8] – 2026-11-02

### Rättat
- Texten hoppar inte längre när du växlar mellan visning och redigering. Fältytan ritas nu runt hela stycket eller raden utan att ta plats, så varje textrad behåller sin höjd.
- Texten "Rättar anonymiserad text" (eller "Rättar originaltexten") ligger nu precis vid knappen Redigera/Klar i stället för som en stor etikett på titelraden. Knappen Redigera/Klar sitter bredvid valet Stycken/Rader.

## [0.7.7] – 2026-11-02

### Ändrat
- Texten hoppar inte längre när du slår på redigeringsläget. Rutan med instruktionen ovanför texten är borttagen, och texten har samma mått och radavstånd i visnings- och redigeringsläget.
- Det syns tydligare att du redigerar: varje stycke får en fältyta med kant, titelraden visar vilken text du rättar ("Redigerar anonymiserad text" eller "Redigerar originaltexten"), och knappen heter "Klar". Esc stänger redigeringsläget, och ändringarna sparas.
- Du rättar nu den text som visas. Med anonymisering på rättar du den anonymiserade texten, och ändringen förs tillbaka till originalet utan att de dolda uppgifterna skrivs över. Rör du själv en platshållare som [PERSON 1] ersätts den dolda uppgiften med det du skrev. Ett stycke som inte går att koppla tillbaka till originalet kan inte rättas med anonymiseringen på.
- Tidskoden för stycken och rader visar en play-ikon och en mjuk bakgrund när du pekar på den, så att det syns att den går att klicka på. Träffytan är lika stor i stycken och rader.

## [0.7.6] – 2026-11-01

### Rättat
- Inställningsraden och dess popover heter nu "Ny transkribering", som i sidopanelen och menyn, i stället för "Nästa transkribering".

## [0.7.5] – 2026-11-01

### Rättat
- Inställningsrutan för en utförd transkribering visar nu modell, språk och talarval som filen har, inte dina standardinställningar. Tidigare kunde chipsen visa KB Large medan rutan visade Pianissimo.
- "Transkribera igen" använder det chipsen visar. Ändrar du inget görs omtagningen med samma modell och språk som filen, inte med dina standardinställningar.
- Modellchipen visar bara modellens namn, utan tillägg som "(Nemotron 3)" som egentligen gäller talarigenkänningen.
- Länken i rutan heter nu "Återställ till det filen har".

## [0.7.4] – 2026-11-01

### Ändrat
- Inställningarna för nästa transkribering och släppytan ligger nu i samma ruta, "Ny transkribering", överst i sidopanelen.
- Val i sidopanelen följer macOS: ett klick väljer raden, ⌘-klick lägger till eller tar bort en rad, ⇧-klick väljer en följd, och Esc avmarkerar allt så att vyn blir tom. Ett vanligt klick på en vald rad avmarkerar inte längre.

### Rättat
- Att välja i sidopanelen svarar direkt igen, var du än klickar på raden. I 0.7.3 svarade bara texten och klicken kändes sega.

## [0.7.3] – 2026-11-01

### Nytt
- Du kan välja flera transkriberingar i sidopanelen med ⌘-klick (enstaka) eller ⇧-klick (följd). Huvudytan visar de valda med knapparna **Transkribera N igen**, **Exportera för analys…** och **Radera N…**. Både omtagning och radering frågar först och säger hur många som berörs.

### Rättat
- **Transkribera igen** är grå så länge valen är samma som filen transkriberades med, och blir blå när du ändrar modell, språk eller talare.
- Ett klick på den transkribering som redan är vald avmarkerar den, och vyn blir tom.

## [0.7.2] – 2026-11-01

### Rättat
- Raden med inställningar för nästa transkribering sitter nu kloss i toppen av vyn i stället för mitt i fönstret.
- Titelkortet och videobilden fälls ihop när du skrollar i en transkribering. Skrollpositionen läses nu direkt från skrollytan.

## [0.7.1] – 2026-11-01

### Rättat
- Sidopanelen har nu en synlig släppyta med "Välj filer…" (den markeras när du drar en fil över fönstret). Sökfältet ligger under rubriken Transkriberingar.
- Modell och språk för nästa transkribering ligger högst upp i sidopanelen i stället för längst ner. Knappen öppnar inställningarna (modell, språk, talare, ordlista); den startar ingenting.
- På en utförd transkribering är chipsen för modell, språk och talare nu knappar. Du väljer andra värden och trycker **Transkribera igen**. Valen gäller bara den omtagningen, dina vanliga inställningar ändras inte.
- Den hopfällda raden vid skroll mäts om och ska nu fällas ihop. För videofiler visas en liten bild i raden; med knappen Bildstorlek väljer du liten, mellan eller stor.

## [0.7.0] – 2026-11-01

### Ändrat
- Inställningarna under Transkribering ligger i ny ordning: Språk, Talare, Ordlista, Ordträff, Tidsstämplar, Mötesinspelning och Experiment sist. Samma val som förut.
- Mötesinspelning har ett statuskort överst (röd tid och "Spelar in" under inspelning, knappen Stoppa och transkribera) och en högerpanel med "Spela även in min mikrofon" och inställningarna som inspelningen transkriberas med. Texten skapas som förut när du stoppar.
- Ny vy för en transkribering: chips överst (modell, språk, antal talare) med **Transkribera igen**, ett titelkort med status, titel, intervjuare, **Sök i texten** och **Exportera**, verktygen (Redigera, Anonymisera, Talare, Kopiera text) och Stycken/Rader, spelaren i ett eget kort, och texten med tunna avdelare. Talarraden har en ▾-meny, tidskod och "Spelas nu". När du skrollat förbi titelkortet ligger en smal rad kvar överst med spela/pausa, skjutreglage, titel, verktygen som ikoner, sök och Exportera.
- **Transkribera igen** frågar nu först, eftersom det ersätter rättningar och talarnamn och inte går att ångra.
- Nytt fönster: en växlare överst mellan **Fil** och **Mötesinspelning** (en röd prick syns på Mötesinspelning medan det spelas in). Sidopanelen har "Välj filer…", antalet transkriberingar, sök, listan med längd, datum och status (Klar, Transkriberar, I kö, Misslyckades) och längst ner modell och språk. Du kan släppa filer var som helst i fönstret.
- Utan vald transkribering visar Fil-läget chips för nästa transkribering (Modell, Språk, Talare, Ordlista) som öppnar sina val.
- Ny accentfärg (indigo) och en egen varningsfärg som är lättare att läsa, i ljust och mörkt läge och med Öka kontrast. Förut hade accentfärgen för låg kontrast mot vitt och varningar var orange.
- Talare visas med en liten färgprick och namnet i vanlig textfärg, så att färgen inte ensam bär informationen.
- Texten du läser är 15 punkter som standard. Under Visa kan du välja Större text (⌘+), Mindre text (⌘−) och Normal storlek (⌘0).
- Stycket som spelas just nu får en accentlinje till vänster och tydligare bakgrund.

## [0.6.3] – 2026-10-31

### Ändrat
- Modellväljaren har bara tre modeller: **Pianissimo** (förstaval för svenska, snabbast), **KB Large ordagrann** (när varje ord måste stämma, t.ex. citat, namn och facktermer) och **Large v3 Turbo** (andra språk än svenska). Pianissimo är nu standard. De andra modellerna är dolda, inte borttagna, och redan nedladdade modeller ligger kvar. Hade du valt en dold modell byter appen till Pianissimo och väljaren visar "(ersätter …)" tills du väljer själv.

## [0.6.2] – 2026-10-31

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
