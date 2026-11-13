import AppKit
import SwiftUI
import TranskriberaCore
import TranskriberaSpeakers

struct SettingsView: View {
    var body: some View {
        TabView {
            TranscriptionSettingsView()
                .tabItem { Label("Transkribering", systemIcon: .transcription) }
            ModelSettingsView()
                .tabItem { Label("Modeller", systemIcon: .models) }
            PrivacySettingsView()
                .tabItem { Label("Integritet", systemIcon: .privacy) }
            UpdateSettingsView()
                .tabItem { Label("Uppdateringar", systemIcon: .updates) }
        }
        .frame(width: 520)
        .padding(20)
    }
}

private struct TranscriptionSettingsView: View {
    @AppStorage(SettingsKey.language) private var language = "sv"
    @AppStorage(SettingsKey.task) private var task = "transcribe"
    @AppStorage(SettingsKey.identifySpeakers) private var identifySpeakers = false
    @AppStorage(SettingsKey.speakers) private var speakers = SpeakerCount.automatic.rawValue
    @AppStorage(SettingsKey.sortformerDiarization) private var sortformerDiarization = true
    @AppStorage(SettingsKey.vocabulary) private var vocabulary = ""
    @AppStorage(SettingsKey.wordTimestamps) private var wordTimestamps = true
    @AppStorage(SettingsKey.recordMicrophone) private var recordMicrophone = true
    @AppStorage(SettingsKey.pianissimoCarefulSeams) private var carefulSeams = false
    @AppStorage(SettingsKey.rescueShortReplies) private var rescueShortReplies = false
    @AppStorage(SettingsKey.crossCheck) private var crossCheck = CrossCheckSource.off
    @AppStorage(SettingsKey.levelVolume) private var levelVolume = true
    @AppStorage(SettingsKey.askBeforeRetranscribe) private var askBeforeRetranscribe = true
    @AppStorage(SettingsKey.model) private var modelRaw = WhisperModel.default.rawValue

    private var usesParakeet: Bool { WhisperModel.resolved(modelRaw).usesParakeet }

    var body: some View {
        Form {
            Section {
                Picker("Språk", selection: $language) {
                    ForEach(Language.all) { language in
                        Text(language.name).tag(language.id)
                    }
                }
                Picker("Resultat", selection: $task) {
                    Text("Text på originalspråket").tag("transcribe")
                    Text("Översätt till engelska").tag("translate")
                }
            } header: {
                Text("Språk")
            } footer: {
                Text("Välj språket som talas. Automatiskt fungerar oftast, men ett angivet språk ger säkrare resultat. Inställningarna gäller nya transkriberingar.")
                    .foregroundStyle(Color.textSecondary)
            }

            Section {
                Toggle("Skilj på vem som pratar", isOn: $identifySpeakers)
                SpeakerCountPicker(selection: $speakers)
                    .disabled(!identifySpeakers)
                Toggle("Bättre på korta svar (Nemotron 3)", isOn: $sortformerDiarization)
                    .disabled(!identifySpeakers || !ShortReplyDiarizer.isSupported)
                    .help("NVIDIAs modell för korta repliker och snabba byten, med högst åtta talare. Används när antal talare är automatiskt; med ett valt antal används den vanliga talaridentifieringen. Körs lokalt.")
            } header: {
                Text("Talare")
            } footer: {
                Text(ShortReplyDiarizer.isSupported
                     ? "Märker texten med Talare 1, Talare 2 … som du kan byta namn på. Vet du hur många som pratar blir uppdelningen säkrare. Nemotron 3 är på som standard men gäller bara med automatiskt antal talare, och laddar ner en modell på några hundra MB första gången. Går det inte används den vanliga talaridentifieringen (cirka 30 MB)."
                     : "Märker texten med Talare 1, Talare 2 … som du kan byta namn på. Vet du hur många som pratar blir uppdelningen säkrare. Laddar ner en extra modell (cirka 30 MB) första gången och tar lite längre tid. Nemotron 3 kräver macOS 15 eller senare.")
                    .foregroundStyle(Color.textSecondary)
            }

            Section {
                TextField("Ordlista", text: $vocabulary, prompt: Text("TG, TB, bruttovinst, Fortnox"), axis: .vertical)
                    .readablePrompt("TG, TB, bruttovinst, Fortnox")
                    .lineLimit(2...4)
            } header: {
                Text("Ordlista")
            } footer: {
                Text("Namn och fackord som brukar förekomma, med komma emellan. Modellen får dem som ledtråd och stavar dem oftare rätt. Namn (med stor bokstav) som ändå hörs nästan rätt, t.ex. ”Fotnox”, rättas i efterhand. Håll listan kort.")
                    .foregroundStyle(Color.textSecondary)
            }

            Section {
                Toggle("Jämna ut volymen", isOn: $levelVolume)
                    .disabled(usesParakeet)
                    .help("Förstärker svaga röster innan ljudet transkriberas. Tystnad och starka röster lämnas som de är. Gav färre ordfel med KB-Whisper i två intervjuer. Pianissimo jämnar ut volymen själv, så där gör valet ingenting.")
            } header: {
                Text("Ordträff")
            } footer: {
                Text("Är på som standard och gäller KB-Whisper och andra Whisper-modeller. Pianissimo jämnar ut volymen själv.")
                    .foregroundStyle(Color.textSecondary)
            }

            Section {
                Toggle("Tidsstämplar per ord", isOn: $wordTimestamps)
            } header: {
                Text("Tidsstämplar")
            } footer: {
                Text("Gör att ordet som spelas upp markeras i texten och att långa undertexter delas upp bättre vid export.")
                    .foregroundStyle(Color.textSecondary)
            }

            if MeetingRecorder.supportsMicrophone {
                Section {
                    Toggle("Spela även in min mikrofon", isOn: $recordMicrophone)
                } header: {
                    Text("Mötesinspelning")
                } footer: {
                    Text("Ta med din egen röst. Annars spelas bara datorns ljud in, alltså de andra deltagarna.")
                        .foregroundStyle(Color.textSecondary)
                }
            }

            Section {
                Toggle("Noggrannare skarvar", isOn: $carefulSeams)
                    .disabled(!usesParakeet)
                    .help("Pianissimo lyssnar på 15 sekunder i taget. Med det här provar den flera sätt att skarva bitarna och väljer det säkraste.")
                Toggle("Fånga korta svar", isOn: $rescueShortReplies)
                    .disabled(!usesParakeet || !identifySpeakers)
                    .help("Korta svar som \"Ja.\" och \"Mm.\" som saknas i texten transkriberas för sig och läggs in efter meningen de hördes i. Resten av texten ändras inte. Kräver \"Skilj på vem som pratar\".")
                Picker("Korskolla", selection: $crossCheck) {
                    ForEach(CrossCheckSource.allCases) { Text($0.label).tag($0) }
                }
                .disabled(!usesParakeet)
                .help("Ljudet transkriberas en gång till. Där körningarna hörde olika ord blir ordet prickat understruket; klicka på det för att välja och lyssna. KB Large tar cirka 25 gånger längre tid. Pianissimo i repliker går fort men kräver \"Skilj på vem som pratar\".")
            } header: {
                Text("Experiment")
            } footer: {
                Text("Ännu inte bevisat bättre. Gäller bara Pianissimo; noggrannare skarvar tar 10–50 % längre tid. Det som användes står på raden Modell i exporten för analys.")
                    .foregroundStyle(Color.textSecondary)
            }

            Section {
                Toggle("Fråga innan Transkribera igen", isOn: $askBeforeRetranscribe)
            } header: {
                Text("Transkribera igen")
            } footer: {
                Text("Den nuvarande versionen sparas, och appen behåller de \(VersionHistory.capacity) senaste versionerna. Frågan visas alltid när den äldsta versionen skulle raderas, även om du har stängt av den här.")
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct PrivacySettingsView: View {
    @AppStorage(SettingsKey.anonymize) private var anonymize = true
    @AppStorage(SettingsKey.anonymizeNames) private var names = true
    @AppStorage(SettingsKey.anonymizeIdentifiers) private var identifiers = true
    @AppStorage(SettingsKey.anonymizeSensitive) private var sensitive = true
    @AppStorage(SettingsKey.anonymizeOrganizations) private var organizations = false
    @AppStorage(SettingsKey.anonymizeUncertainNames) private var uncertainNames = false
    @AppStorage(SettingsKey.anonymizeAlwaysHide) private var alwaysHide = ""
    @AppStorage(SettingsKey.anonymizeNeverHide) private var neverHide = ""

    var body: some View {
        Form {
            Section {
                Toggle("Anonymisera känsliga uppgifter", isOn: $anonymize)
            } footer: {
                Text("Uppgifterna ersätts med t.ex. [PERSON 1] när du läser, kopierar och exporterar. Originaltexten sparas och visas igen om du stänger av det här. Allt sker lokalt på datorn.")
                    .foregroundStyle(Color.textSecondary)
            }

            Section {
                Toggle("Namn på personer och platser", isOn: $names)
                Toggle("Företag och organisationer", isOn: $organizations)
                    .help("Av som standard. Namn som Fortnox och Visma behövs oftast för att förstå texten.")
                Toggle("Andra ord som ser ut som namn", isOn: $uncertainNames)
                    .help("Döljer även ord med stor bokstav som inte går att känna igen. Säkrare, men döljer ofta vanliga ord som Euro eller Rabatt.")
                Toggle("Personnummer, telefon, e-post, adresser, konto- och kortnummer, regnummer", isOn: $identifiers)
                Toggle("Hälsa, religion, politisk åsikt m.m.", isOn: $sensitive)
            } header: {
                Text("Vad som döljs")
            } footer: {
                Text("Hälsa, religion och liknande hittas bara delvis, via en ordlista. Ingen automatisk anonymisering är helt säker, så läs igenom texten innan du delar den.")
                    .foregroundStyle(Color.textSecondary)
            }
            .disabled(!anonymize)

            Section {
                TextField("Dölj alltid", text: $alwaysHide, prompt: Text("Rasmus, Joj"), axis: .vertical)
                    .readablePrompt("Rasmus, Joj")
                    .lineLimit(1...3)
                TextField("Dölj aldrig", text: $neverHide, prompt: Text("Euro, Rabatt, Visma"), axis: .vertical)
                    .readablePrompt("Euro, Rabatt, Visma")
                    .lineLimit(1...3)
            } header: {
                Text("Egna undantag")
            } footer: {
                Text("Skriv ord med komma emellan. Namnen under Dölj alltid döljs som personer även när de är felstavade på samma sätt eller skrivna med liten bokstav.")
                    .foregroundStyle(Color.textSecondary)
            }
            .disabled(!anonymize)
        }
        .formStyle(.grouped)
    }
}

private struct ModelSettingsView: View {
    @AppStorage(SettingsKey.model) private var modelRaw = WhisperModel.default.rawValue
    @Environment(TranscriptionQueue.self) private var queue
    @State private var refresh = 0
    @State private var showsGuide = false

    var body: some View {
        let transcriber = queue.transcriber
        Form {
            Section {
                LabeledContent("Modell") {
                    ModelPicker(selection: $modelRaw)
                        .frame(maxWidth: 260)
                }
                Button("Vilken modell ska jag välja?") { showsGuide = true }
                    .help("Jämförelse av modellerna och råd om när du ska välja vilken")
                    .sheet(isPresented: $showsGuide) {
                        VStack(spacing: 0) {
                            ModelGuideView()
                            Divider()
                            HStack {
                                Spacer()
                                Button("Klar") { showsGuide = false }
                                    .keyboardShortcut(.defaultAction)
                            }
                            .padding(12)
                        }
                            .presentationRoot()
                    }
            } footer: {
                Text("Pianissimo är snabbast och bäst som förstaval för svenska. Välj Large v3 Turbo för andra språk. Modellen laddas ner automatiskt första gången den används.")
                    .foregroundStyle(Color.textSecondary)
            }

            ForEach(WhisperModel.Family.allCases) { family in
                Section {
                    ForEach(family.models) { model in
                        HStack(alignment: .top, spacing: 12) {
                            ModelInfoRow(model: model, isDownloaded: transcriber.isDownloaded(model))
                            if transcriber.isDownloaded(model) {
                                Button("Ta bort", role: .destructive) {
                                    transcriber.deleteDownloadedModel(model)
                                    refresh += 1
                                }
                                .disabled(transcriber.isBusy)
                                .help("Frigör utrymme. Modellen laddas ner igen om du använder den.")
                            } else {
                                Button("Ladda ner") {
                                    Task {
                                        _ = try? await transcriber.prepare(model: model)
                                        refresh += 1
                                    }
                                }
                                .disabled(transcriber.isBusy)
                                .help("Hämta modellen nu så att den är redo direkt")
                            }
                        }
                    }
                    .id(refresh)
                } header: {
                    Text(family.title)
                }
            }

            Section {
                if transcriber.isBusy {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(transcriber.statusText).font(.app(.small))
                    }
                }
                Button("Visa modellmappen i Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([AppPaths.modelsDirectory])
                }
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Modellerna sparas på din Mac. Ta bort dem du inte använder för att frigöra utrymme.")
                        .foregroundStyle(Color.textSecondary)
                    ModelSourceNote()
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Antal talare: automatiskt (0) eller ett känt antal.
struct SpeakerCountPicker: View {
    /// `SpeakerCount.rawValue`.
    @Binding var selection: String

    var body: some View {
        Picker("Antal talare", selection: $selection) {
            ForEach(SpeakerCount.choices) { count in
                Text(count.label).tag(count.rawValue)
            }
        }
        .help("Vet du hur många som pratar blir uppdelningen säkrare. Ett spann, t.ex. 2–4, passar när du inte vet hur många som är med från kundsidan.")
    }
}
