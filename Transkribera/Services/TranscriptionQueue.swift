import Foundation
import Observation
import SwiftData

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
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var currentJob: Task<TranscriptionOutput, Error>?

    init(transcriber: TranscriberService, context: ModelContext) {
        self.transcriber = transcriber
        self.context = context
        resumeUnfinished()
    }

    var queuedCount: Int { pending.count }

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
            modelName: TranscriptionOptions.fromDefaults().model.displayName,
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

    func retranscribe(_ transcript: Transcript) {
        enqueue(transcript)
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
        guard worker == nil else { return }
        worker = Task { [weak self] in
            while let self, !self.pending.isEmpty {
                let next = self.pending.removeFirst()
                await self.process(next)
            }
            self?.worker = nil
        }
    }

    private func process(_ transcript: Transcript) async {
        let options = TranscriptionOptions.fromDefaults()
        currentTranscriptID = transcript.id
        transcript.status = .transcribing
        transcript.modelName = options.model.displayName
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
            transcript.replaceSegments(with: output.segments, in: context)
            transcript.language = output.language
            transcript.status = .completed
            transcript.errorMessage = output.segments.isEmpty ? "Inget tal hittades i filen." : nil
        } catch is CancellationError {
            transcript.status = transcript.segments.isEmpty ? .failed : .completed
            transcript.errorMessage = transcript.segments.isEmpty ? "Avbruten" : nil
        } catch {
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
