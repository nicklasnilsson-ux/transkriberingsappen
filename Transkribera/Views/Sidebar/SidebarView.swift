import AppKit
import SwiftData
import SwiftUI
import TranskriberaCore

struct SidebarView: View {
    @Binding var selection: Transcript?
    @Binding var multiSelection: [Transcript]
    @Environment(TranscriptionQueue.self) private var queue
    @Environment(AppState.self) private var appState
    @Environment(MeetingRecorder.self) private var recorder
    @AppStorage(SettingsKey.model) private var modelRaw = WhisperModel.default.rawValue
    @AppStorage(SettingsKey.language) private var language = "sv"
    @AppStorage(SettingsKey.identifySpeakers) private var identifySpeakers = false
    @AppStorage(SettingsKey.vocabulary) private var vocabulary = ""
    @Query(sort: \Transcript.createdAt, order: .reverse) private var transcripts: [Transcript]
    @State private var filter = ""
    @State private var transcriptToDelete: Transcript?
    @State private var transcriptToRetranscribe: Transcript?
    @AppStorage(SettingsKey.askBeforeRetranscribe) private var askBeforeRetranscribe = true
    @State private var showsNextSettings = false
    /// Listans val som mängd: en eller flera. Flera ligger i `multiSelection`, en i `selection`.
    private var listSelection: Binding<Set<Transcript>> {
        Binding(
            get: { multiSelection.count > 1 ? Set(multiSelection) : (selection.map { [$0] } ?? []) },
            set: { newValue in
                if newValue.count > 1 {
                    multiSelection = Array(newValue)
                    selection = nil
                } else {
                    multiSelection = []
                    selection = newValue.first
                }
            }
        )
    }

    private var filtered: [Transcript] {
        guard !filter.isEmpty else { return transcripts }
        return transcripts.filter { TextSearch.matches($0.title, query: filter) }
    }

    private struct TranscriptGroup: Identifiable {
        let group: SidebarGroup
        let items: [Transcript]
        var id: String { group.rawValue }
    }

    private var groups: [TranscriptGroup] {
        let now = Date()
        return SidebarGroup.allCases.compactMap { group in
            let items = filtered.filter { SidebarGroup.group(for: $0.createdAt, now: now) == group }
            return items.isEmpty ? nil : TranscriptGroup(group: group, items: items)
        }
    }

    var body: some View {
        // Allt i panelen ligger i en enda scrollvy, uppifrån och ned som en webbsida: rutan för ny transkribering,
        // rubriken, sökfältet och listan. Ingen mätning, ingen centrering och ingen egen höjd som kan trycka ut något
        // ovanför fönstret (Nicklas 2026-11-04, fyra gånger).
        list
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        .confirmationDialog(
            "Radera ”\(transcriptToDelete?.title ?? "")”?",
            isPresented: Binding(get: { transcriptToDelete != nil }, set: { if !$0 { transcriptToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Radera", role: .destructive) {
                if let transcript = transcriptToDelete {
                    if selection == transcript { selection = nil }
                    multiSelection.removeAll { $0 == transcript }
                    queue.delete(transcript)
                }
                transcriptToDelete = nil
            }
        } message: {
            Text(transcriptToDelete?.isRecording == true
                 ? "Texten och inspelningen raderas. Det går inte att ångra."
                 : "Texten och appens kopia av filen raderas. Originalfilen påverkas inte. Det går inte att ångra.")
        }
        .sheet(item: $transcriptToRetranscribe) { transcript in
            RetranscribeSheet(
                versionCount: transcript.versionCount,
                oldestDescription: transcript.oldestVersionDescription,
                onCancel: { transcriptToRetranscribe = nil },
                onConfirm: {
                    if let confirmation = RetranscribeConfirmation(replacingText: !transcript.segments.isEmpty, confirmed: true) {
                        queue.retranscribe(transcript, confirmation: confirmation)
                    }
                    transcriptToRetranscribe = nil
                }
            )
        }
        .onDeleteCommand {
            if multiSelection.count > 1 {
                appState.requestBulkDelete = true
            } else if let selection {
                transcriptToDelete = selection
            }
        }
    }

    /// Överst i panelen: inställningskortet och rutan för ny transkribering, i samma listrad.
    /// Inställningarna gäller både Fil och Mötesinspelning och finns bara här (Nicklas 2026-11-05):
    /// ingen rad med väljare i huvudytan, som trycktes ihop när fönstret var smalt.
    private var topCards: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingsCard
            newTranscriptionGroup
        }
        .padding(.top, 10)
    }

    /// Släppytan eller mötesinspelningen, under Fil/Mötesinspelning.
    private var newTranscriptionGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ny transkribering")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .padding(.leading, 2)
            modeSwitcher
            // I mötesläget ersätter inspelningen släppytan: man gör en sak i taget.
            if appState.mode == .meeting {
                MeetingControls()
            } else {
                dropArea
            }
        }
        .padding(10)
        .sidebarCard()
    }

    /// Fil eller Mötesinspelning. Ligger överst i sidopanelen (inte i fönstrets verktygsfält), så
    /// att titelbaren är fri för det som hör till den öppnade texten.
    private var modeSwitcher: some View {
        Picker("Läge", selection: Binding(
            get: { appState.mode },
            set: { appState.mode = $0; appState.clearSelection() }
        )) {
            Text("Fil").tag(AppMode.file)
            Label("Mötesinspelning", icon: .circle)
                .labelStyle(RecordingDotLabelStyle(isRecording: recorder.isRecording))
                .tag(AppMode.meeting)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .help("Fil: transkribera ljud- och videofiler. Mötesinspelning: spela in datorns ljud.")
    }

    /// Inställningskortet: rubrik, modell och språk, och en rad till bara när något mer är på.
    /// Klick öppnar formuläret med alla val för nästa transkribering.
    private var settingsCard: some View {
        let summary = NextTranscriptionSummary(
            modelName: WhisperModel.resolved(modelRaw).displayName,
            languageName: Language.displayName(for: language),
            identifySpeakers: identifySpeakers,
            hasVocabulary: !vocabulary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            modelDownloaded: queue.transcriber.isDownloaded(WhisperModel.resolved(modelRaw))
        )
        return Button { showsNextSettings.toggle() } label: {
            SettingsCardLabel(summary: summary)
        }
        .buttonStyle(.plain)
        // Låst under mötesinspelning: inställningarna gäller inspelningen som pågår.
        .disabled(recorder.isBusy)
        .opacity(recorder.isBusy ? 0.55 : 1)
        .help("Inställningar för ny transkribering, både fil och mötesinspelning: modell, språk, talare och ordlista")
        .accessibilityLabel("Inställningar: \(summary.accessibilityText)")
        .popover(isPresented: $showsNextSettings, arrowEdge: .trailing) {
            NextTranscriptionSettingsForm()
        }
    }

    /// Släppyta med knappen Välj filer…. Hela fönstret tar emot filer; den här visar var.
    private var dropArea: some View {
        VStack(spacing: 8) {
            Icon(appState.isDropTargeted ? .downloadCircle : .download, size: 26)
                .foregroundStyle(appState.isDropTargeted ? Color.accentColor : Color.textSecondary)
            Text("Släpp ljud- eller videofiler här")
                .font(.callout)
                .multilineTextAlignment(.center)
            Button("Välj filer…") { appState.isImporterPresented = true }
                .help("Välj ljud- eller videofiler att transkribera (⌘O)")
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    appState.isDropTargeted ? Color.accentColor : Color.textSecondary.opacity(0.5),
                    style: StrokeStyle(lineWidth: appState.isDropTargeted ? 2 : 1, dash: appState.isDropTargeted ? [] : [6, 4])
                )
        }
    }

    private var listHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Transkriberingar (\(transcripts.count))")
                .font(.headline)
            HStack(spacing: 6) {
                Image(icon: .search).foregroundStyle(Color.textSecondary)
                TextField("Sök på titel", text: $filter)
                    .textFieldStyle(.plain)
                if !filter.isEmpty {
                    Button { filter = "" } label: { Image(icon: .cancel) }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.textSecondary)
                        .help("Rensa sökningen")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.chip, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    private var list: some View {
        List(selection: listSelection) {
            topCards.sidebarPlainRow()
            listHeader.sidebarPlainRow()

            if transcripts.isEmpty {
                Text("Inga transkriberingar än. Släpp en fil eller spela in ett möte så hamnar resultatet här.")
                    .font(.callout)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.top, 8)
            }

            ForEach(groups) { group in
                Section(group.group.rawValue) {
                    ForEach(group.items) { transcript in
                        SidebarRow(
                            transcript: transcript,
                            isCurrent: queue.currentTranscriptID == transcript.id,
                            isSelected: listSelection.wrappedValue.contains(transcript)
                        )
                            .tag(transcript)
                            .contextMenu { menu(for: transcript) }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color.sidebarBackground)
    }

    /// Frågar först när något ska sparas eller raderas (se `RetranscribeDialog`).
    private func requestRetranscribe(_ transcript: Transcript) {
        let hasText = !transcript.segments.isEmpty
        if hasText, RetranscribeDialog.needsDialog(versionCount: transcript.versionCount, askSetting: askBeforeRetranscribe) {
            transcriptToRetranscribe = transcript
        } else if let confirmation = RetranscribeConfirmation(replacingText: hasText, confirmed: true) {
            queue.retranscribe(transcript, confirmation: confirmation)
        }
    }

    @ViewBuilder
    private func menu(for transcript: Transcript) -> some View {
        Button("Transkribera igen med nuvarande inställningar…") { requestRetranscribe(transcript) }
            .disabled(transcript.status == .transcribing || transcript.status == .queued)
        Button("Visa ljud-/videofilen i Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([transcript.mediaURL])
        }
        Divider()
        Button("Radera…", role: .destructive) { transcriptToDelete = transcript }
    }
}

/// Rutan, rubriken och sökfältet ska ha samma kanter som markeringen av en rad.
/// Uppmätt i CI (SidebarMarginTests, macOS 26): listan lägger varje rads innehåll 16 pt in från panelens
/// sidor, men ritar markeringen bara 10 pt in. Raderna utan markering flyttas därför ut 6 pt (negativ marginal)
/// så att deras kanter hamnar på markeringens. Transkriberingsraderna behåller listans egen marginal.
private enum SidebarLayout {
    static let cellInset: CGFloat = 16
    static let selectionInset: CGFloat = 10
    static let plainRowInset: CGFloat = selectionInset - cellInset
}

private struct SidebarRow: View {
    let transcript: Transcript
    let isCurrent: Bool
    /// Raden är vald i listan. `backgroundProminence` räckte inte: 0.9.7 hade fortfarande mörk text på markeringen.
    let isSelected: Bool
    @Environment(TranscriptionQueue.self) private var queue
    /// Markeringen är grå när fönstret inte är i fokus; då ska texten inte vara vit.
    @Environment(\.controlActiveState) private var activeState

    private var isOnSelection: Bool { isSelected && activeState != .inactive }
    private var primaryColor: Color { isOnSelection ? .white : .textPrimary }
    private var secondaryColor: Color { isOnSelection ? .white.opacity(0.85) : .textSecondary }

    var body: some View {
        HStack(spacing: 10) {
            icon
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(transcript.title)
                    .lineLimit(1)
                    .font(.body.weight(.medium))
                    .foregroundStyle(primaryColor)
                Text(detail)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(secondaryColor)
                    .lineLimit(1)
                Text(statusLabel.text)
                    .font(.caption)
                    .foregroundStyle(statusLabel.isWarning && !isOnSelection ? Color.warning : secondaryColor)
            }
        }
        .padding(.vertical, 3)
        // En rad är ett enda objekt för skärmläsare: titel, längd, datum och status i en mening.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        [transcript.title, detail, statusLabel.text].joined(separator: ", ")
    }

    @ViewBuilder
    private var icon: some View {
        switch transcript.status {
        case .transcribing where isCurrent:
            if let fraction = queue.transcriber.fraction {
                ProgressView(value: fraction)
                    .progressViewStyle(.circular)
                    .controlSize(.small)
            } else {
                ProgressView().controlSize(.small)
            }
        case .queued, .transcribing:
            Image(icon: .clock).foregroundStyle(secondaryColor)
        case .failed:
            Image(icon: .warning).foregroundStyle(isOnSelection ? Color.white : Color.warning)
        case .completed:
            Image(icon: transcript.isRecording ? .record : (transcript.isVideo ? .movie : .waveform))
                .foregroundStyle(isOnSelection ? Color.white : Color.accentColor)
        }
    }

    private var detail: String {
        let date = transcript.createdAt.formatted(date: .abbreviated, time: .shortened)
        return transcript.status == .completed
            ? "\(TimeFormatting.duration(transcript.duration)) · \(date)"
            : date
    }

    private var statusLabel: (text: String, isWarning: Bool) {
        switch transcript.status {
        case .completed: ("Klar", false)
        case .transcribing: ("Transkriberar", false)
        case .queued: ("I kö", false)
        case .failed: ("Misslyckades", true)
        }
    }
}

/// Rubrik i lägesväxlaren: en röd prick (7 pt) före texten medan det spelas in.
private struct RecordingDotLabelStyle: LabelStyle {
    let isRecording: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            if isRecording {
                Circle().fill(Color.red).frame(width: 7, height: 7)
                    .accessibilityLabel("Spelar in")
            }
            configuration.title
        }
    }
}

/// Inställningskortets innehåll. Varje rad är en rad: i en smal panel kortas texten med … i stället för
/// att brytas mitt i orden (felet med väljarna i huvudytan 2026-11-05). `SettingsCardTests` mäter det.
struct SettingsCardLabel: View {
    let summary: NextTranscriptionSummary

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Inställningar")
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(summary.title)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let detail = summary.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 4)
            Image(icon: .tune).foregroundStyle(Color.textSecondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .sidebarCard()
    }
}

extension View {
    /// En rad i sidopanelens lista som inte är en transkribering: ingen markering, ingen bakgrund, inga marginaler
    /// eller avdelare. Innehållet bestämmer själv sina marginaler.
    func sidebarPlainRow() -> some View {
        self
            .listRowInsets(EdgeInsets(top: 0, leading: SidebarLayout.plainRowInset, bottom: 0, trailing: SidebarLayout.plainRowInset))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .selectionDisabled()
    }

    /// Kortets yta i sidopanelen: samma fyllning och kant för inställningskortet och rutan för ny transkribering.
    func sidebarCard() -> some View {
        self
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.chip))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.line, lineWidth: 1))
    }
}
