import AppKit
import SwiftUI
import TranskriberaCore
import TranskriberaSpeakers

struct SettingsView: View {
    var body: some View {
        TabView {
            TranscriptionSettingsView()
                .tabItem { Label("Transkribering", systemImage: "waveform") }
            ModelSettingsView()
                .tabItem { Label("Modeller", systemImage: "cpu") }
            PrivacySettingsView()
                .tabItem { Label("Integritet", systemImage: "hand.raised") }
            UpdateSettingsView()
                .tabItem { Label("Uppdateringar", systemImage: "arrow.triangle.2.circlepath") }
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
    @AppStorage(SettingsKey.communityDiarization) private var communityDiarization = false
    @AppStorage(SettingsKey.sortformerDiarization) private var sortformerDiarization = false
    @AppStorage(SettingsKey.vocabulary) private var vocabulary = ""
    @AppStorage(SettingsKey.wordTimestamps) private var wordTimestamps = true
    @AppStorage(SettingsKey.recordMicrophone) private var recordMicrophone = true
    @AppStorage(SettingsKey.pianissimoCarefulSeams) private var carefulSeams = false
    @AppStorage(SettingsKey.levelVolume) private var levelVolume = true

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
            } footer: {
                Text("Välj språket som talas. Automatiskt fungerar oftast, men ett angivet språk ger säkrare resultat. Inställningarna gäller nya transkriberingar.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Skilj på vem som pratar", isOn: $identifySpeakers)
                SpeakerCountPicker(selection: $speakers)
                    .disabled(!identifySpeakers)
            } footer: {
                Text("Märker texten med Talare 1, Talare 2 … som du kan byta namn på. Vet du hur många som pratar blir uppdelningen säkrare. Laddar ner en extra modell (cirka 30 MB) första gången och tar lite längre tid.")
                    .foregroundStyle(.secondary)
            }

            Section {
                TextField("Ordlista", text: $vocabulary, prompt: Text("TG, TB, bruttovinst, Fortnox"), axis: .vertical)
                    .lineLimit(2...4)
            } header: {
                Text("Ordlista")
            } footer: {
                Text("Namn och fackord som brukar förekomma, med komma emellan. Modellen får dem som ledtråd och stavar dem oftare rätt. Namn (med stor bokstav) som ändå hörs nästan rätt, t.ex. ”Fotnox”, rättas i efterhand. Håll listan kort.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Noggrannare skarvar (Pianissimo)", isOn: $carefulSeams)
                    .help("Pianissimo lyssnar på 15 sekunder i taget. Med det här provar den flera sätt att skarva bitarna och väljer det säkraste.")
                Toggle("Jämna ut volymen (KB-Whisper)", isOn: $levelVolume)
                    .help("Förstärker svaga röster innan ljudet transkriberas. Tystnad och starka röster lämnas som de är. Gav färre ordfel med KB-Whisper i två intervjuer. Pianissimo jämnar ut volymen själv, så där gör valet ingenting.")
                Toggle("Ny talaridentifiering (pyannote community-1)", isOn: $communityDiarization)
                    .disabled(!CommunityDiarizer.isSupported)
                    .help("En nyare modell för att avgöra vem som pratar. Körs lokalt, som den nuvarande. Laddar ner en extra modell första gången.")
                Toggle("Talaridentifiering för korta svar (Nemotron 3)", isOn: $sortformerDiarization)
                    .disabled(!ShortReplyDiarizer.isSupported)
                    .help("NVIDIAs nyaste modell för korta repliker och snabba byten, med högst åtta talare. Går före den nya talaridentifieringen och ignorerar valet av antal talare. Körs lokalt och laddar ner en extra modell första gången.")
            } header: {
                Text("Experiment")
            } footer: {
                Text(CommunityDiarizer.isSupported
                     ? "För att jämföra kvaliteten. Noggrannare skarvar tar 10–50 % längre tid. Det som användes står efter modellens namn i transkriberingen."
                     : "För att jämföra kvaliteten. Noggrannare skarvar tar 10–50 % längre tid. Den nya talaridentifieringen kräver macOS 15 eller senare. Det som användes står efter modellens namn i transkriberingen.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Tidsstämplar per ord", isOn: $wordTimestamps)
            } footer: {
                Text("Gör att ordet som spelas upp markeras i texten och att långa undertexter delas upp bättre vid export.")
                    .foregroundStyle(.secondary)
            }

            if MeetingRecorder.supportsMicrophone {
                Section {
                    Toggle("Spela även in min mikrofon", isOn: $recordMicrophone)
                } header: {
                    Text("Mötesinspelning")
                } footer: {
                    Text("Ta med din egen röst. Annars spelas bara datorns ljud in, alltså de andra deltagarna.")
                        .foregroundStyle(.secondary)
                }
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
                    .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
            }
            .disabled(!anonymize)

            Section {
                TextField("Dölj alltid", text: $alwaysHide, prompt: Text("Rasmus, Joj"), axis: .vertical)
                    .lineLimit(1...3)
                TextField("Dölj aldrig", text: $neverHide, prompt: Text("Euro, Rabatt, Visma"), axis: .vertical)
                    .lineLimit(1...3)
            } header: {
                Text("Egna undantag")
            } footer: {
                Text("Skriv ord med komma emellan. Namnen under Dölj alltid döljs som personer även när de är felstavade på samma sätt eller skrivna med liten bokstav.")
                    .foregroundStyle(.secondary)
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
                    }
            } footer: {
                Text("KB-modellerna är bäst på svenska. Välj en OpenAI-modell för andra språk. Modellen laddas ner automatiskt första gången den används.")
                    .foregroundStyle(.secondary)
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
                        Text(transcriber.statusText).font(.caption)
                    }
                }
                Button("Visa modellmappen i Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([AppPaths.modelsDirectory])
                }
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Modellerna sparas på din Mac. Ta bort dem du inte använder för att frigöra utrymme.")
                        .foregroundStyle(.secondary)
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
