import Foundation
import Observation
import SwiftData
import TranskriberaCore

/// Tar emot filer, sparar dem som `Transcript` och transkriberar dem en i taget.
@MainActor
@Observable
final class TranscriptionQueue {
    let transcriber: TranscriberService
    private let context: ModelContext

    /// Transkriberingen som körs just nu.
    private(set) var currentTranscriptID: UUID?
    /// Felmeddelande från senaste importen (t.ex. filformat som inte stöds).
    var importError: String?

    @ObservationIgnored private var pending: [Transcript] = []
    /// Val som bara gäller en omtagning (se `TranscriptionOverrides`).
    @ObservationIgnored private var overridesByID: [UUID: TranscriptionOverrides] = [:]
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var currentJob: Task<TranscriptionOutput, Error>?

    init(transcriber: TranscriberService, context: ModelContext) {
        self.transcriber = transcriber
        self.context = context
        resumeUnfinished()
    }

    var queuedCount: Int { pending.count }

    /// Skäl till att kön väntar (Testlabbet använder transkriberaren, eller en mötesinspelning
    /// pågår). Nya filer köas men startar först när inget håller kvar kön.
    private(set) var holds = QueueHolds()
    var isHeld: Bool { holds.isHeld }

    /// Sant när inget transkriberas och kön är tom, så att Testlabbet kan ta över.
    var isIdle: Bool { currentTranscriptID == nil && pending.isEmpty && worker == nil }

    func hold() { holds.testLab = true }

    func release() {
        holds.testLab = false
        startWorkerIfNeeded()
    }

    /// Anropas av mötesinspelaren när den börjar och slutar vara upptagen.
    func setRecordingBusy(_ busy: Bool) {
        holds.recording = busy
        if !busy { startWorkerIfNeeded() }
    }

    // MARK: - Import

    /// Importerar filer och lägger dem i kön. Returnerar den första nya transkriberingen.
    @discardableResult
    func importFiles(_ urls: [URL]) async -> Transcript? {
        var first: Transcript?
        var rejected: [String] = []

        for url in urls {
            guard MediaStore.isSupported(url) else {
                rejected.append("\(url.lastPathComponent) (formatet stöds inte)")
                continue
            }
            do {
                let fileName = try MediaStore.importFile(at: url)
                let transcript = try await makeTranscript(
                    mediaFileName: fileName,
                    title: url.deletingPathExtension().lastPathComponent,
                    originalFileName: url.lastPathComponent
                )
                first = first ?? transcript
            } catch {
                rejected.append("\(url.lastPathComponent) (\(error.localizedDescription))")
            }
        }

        if !rejected.isEmpty {
            importError = rejected.joined(separator: "\n")
        }
        return first
    }

    /// Lägger till en inspelning som appen själv har skapat.
    @discardableResult
    func importRecording(at url: URL, title: String) async -> Transcript? {
        do {
            let fileName = try MediaStore.moveFile(at: url)
            return try await makeTranscript(
                mediaFileName: fileName,
                title: title,
                originalFileName: url.lastPathComponent,
                isRecording: true
            )
        } catch {
            importError = "Kunde inte spara inspelningen: \(error.localizedDescription)"
            return nil
        }
    }

    private func makeTranscript(
        mediaFileName: String,
        title: String,
        originalFileName: String,
        isRecording: Bool = false
    ) async throws -> Transcript {
        let info: MediaInfo
        do {
            info = try await AudioLoader.mediaInfo(for: MediaStore.url(for: mediaFileName))
        } catch {
            MediaStore.delete(fileName: mediaFileName)
            throw error
        }
        let transcript = Transcript(
            title: title,
            mediaFileName: mediaFileName,
            originalFileName: originalFileName,
            isVideo: info.isVideo,
            duration: info.duration,
            modelName: TranscriptionOptions.fromDefaults().modelLabel,
            isRecording: isRecording
        )
        context.insert(transcript)
        save()
        enqueue(transcript)
        return transcript
    }

    // MARK: - Kö

    func enqueue(_ transcript: Transcript) {
        guard !pending.contains(where: { $0.id == transcript.id }), currentTranscriptID != transcript.id else { return }
        transcript.status = .queued
        transcript.errorMessage = nil
        pending.append(transcript)
        save()
        startWorkerIfNeeded()
    }

    /// Kräver en bekräftelse (`RetranscribeConfirmation`), eftersom omtagningen ersätter
    /// rättningar och talarnamn. Det går inte att anropa utan.
    func retranscribe(
        _ transcript: Transcript,
        confirmation: RetranscribeConfirmation,
        overrides: TranscriptionOverrides = TranscriptionOverrides()
    ) {
        if overrides.isEmpty {
            overridesByID[transcript.id] = nil
        } else {
            overridesByID[transcript.id] = overrides
        }
        enqueue(transcript)
    }

    /// Flera på en gång; samma krav på bekräftelse som en enda.
    func retranscribe(_ transcripts: [Transcript], confirmation: RetranscribeConfirmation) {
        for transcript in transcripts where transcript.status != .queued && transcript.status != .transcribing {
            retranscribe(transcript, confirmation: confirmation)
        }
    }

    /// Raderar flera. Kräver en bekräftelse (`DeleteConfirmation`), så det går inte utan fråga.
    func delete(_ transcripts: [Transcript], confirmation: DeleteConfirmation) {
        for transcript in transcripts { delete(transcript) }
    }

    func cancel(_ transcript: Transcript) {
        if currentTranscriptID == transcript.id {
            currentJob?.cancel()
        } else if let index = pending.firstIndex(where: { $0.id == transcript.id }) {
            pending.remove(at: index)
            transcript.status = transcript.segments.isEmpty ? .failed : .completed
            transcript.errorMessage = transcript.segments.isEmpty ? "Avbruten" : nil
            save()
        }
    }

    func delete(_ transcript: Transcript) {
        cancel(transcript)
        pending.removeAll { $0.id == transcript.id }
        MediaStore.delete(fileName: transcript.mediaFileName)
        context.delete(transcript)
        save()
    }

    private func startWorkerIfNeeded() {
        guard worker == nil, !isHeld else { return }
        worker = Task { [weak self] in
            while let self, !self.pending.isEmpty, !self.isHeld {
                let next = self.pending.removeFirst()
                await self.process(next)
            }
            self?.worker = nil
        }
    }

    private func process(_ transcript: Transcript) async {
        let options = (overridesByID.removeValue(forKey: transcript.id) ?? TranscriptionOverrides())
            .applied(to: TranscriptionOptions.fromDefaults())
        currentTranscriptID = transcript.id
        transcript.status = .transcribing
        // Modellen som texten som visas gjordes med. Den behövs när den förra versionen sparas,
        // och när körningen avbryts eller misslyckas.
        let previousModelName = transcript.modelName
        transcript.modelName = options.modelLabel
        save()

        let transcriber = self.transcriber
        let url = transcript.mediaURL
        let duration = transcript.duration
        let job = Task { @MainActor in
            try await transcriber.transcribe(fileURL: url, duration: duration, options: options)
        }
        currentJob = job

        do {
            let output = try await job.value
            // Den förra versionen sparas, och de äldsta som inte får plats raderas först nu,
            // när den nya finns (se `Transcript.addNewVersion`).
            transcript.addNewVersion(output, previousModelName: previousModelName, in: context)
            transcript.status = .completed
            transcript.errorMessage = output.segments.isEmpty ? "Inget tal hittades i filen." : nil
        } catch is CancellationError {
            if !transcript.segments.isEmpty { transcript.modelName = previousModelName }
            transcript.status = transcript.segments.isEmpty ? .failed : .completed
            transcript.errorMessage = transcript.segments.isEmpty ? "Avbruten" : nil
        } catch {
            if !transcript.segments.isEmpty { transcript.modelName = previousModelName }
            transcript.status = .failed
            transcript.errorMessage = error.localizedDescription
        }

        currentJob = nil
        currentTranscriptID = nil
        save()
    }

    /// Transkriberingar som inte blev klara förra gången appen kördes läggs i kön igen.
    private func resumeUnfinished() {
        let descriptor = FetchDescriptor<Transcript>(sortBy: [SortDescriptor(\.createdAt)])
        guard let all = try? context.fetch(descriptor) else { return }
        for transcript in all where transcript.status == .queued || transcript.status == .transcribing {
            enqueue(transcript)
        }
    }

    private func save() {
        do {
            try context.save()
        } catch {
            print("Kunde inte spara: \(error)")
        }
    }
}
