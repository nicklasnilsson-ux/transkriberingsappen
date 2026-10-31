import Foundation
import TranskriberaCore

/// Testlabbet kör samma inspelning med flera inställningar efter varandra och sparar
/// varje text, en logg per körning och en sammanfattning i en mapp, så att inställningarna
/// går att jämföra mot ett facit. Vanliga transkriberingar påverkas inte.
@MainActor
@Observable
final class TestLab {
    enum Status: Equatable {
        case waiting
        case running
        case done(seconds: Double)
        case failed(String)
        case skipped
        case cancelled
    }

    let plan = TestLabPlan.standard
    var selected = Set(TestLabPlan.standard.map(\.id))
    private(set) var statuses: [String: Status] = [:]
    private(set) var isRunning = false
    /// Vad som händer just nu, t.ex. "Körning 3 av 13: KB: utan upprepningsspärr".
    private(set) var stepText = ""
    /// Mappen som den senaste körningen skrev till.
    private(set) var folder: URL?
    private(set) var message: String?
    @ObservationIgnored private var task: Task<Void, Never>?

    static var baseDirectory: URL {
        AppPaths.supportDirectory.appending(path: "Testlabb", directoryHint: .isDirectory)
    }

    /// Ljudet som går att köra: färdiga transkriberingar vars mediafil finns kvar.
    static func canRun(_ transcript: Transcript) -> Bool {
        transcript.status == .completed && FileManager.default.fileExists(atPath: transcript.mediaURL.path)
    }

    func start(transcript: Transcript, queue: TranscriptionQueue) {
        guard !isRunning else { return }
        guard queue.isIdle else {
            message = "Vänta tills transkriberingarna i kön är klara. Testlabbet och vanliga transkriberingar kan inte köra samtidigt."
            return
        }
        let runs = plan.filter { selected.contains($0.id) }
        guard !runs.isEmpty else { return }

        let source = Source(
            title: transcript.title,
            createdAt: transcript.createdAt,
            duration: transcript.duration,
            mediaURL: transcript.mediaURL
        )
        queue.hold()
        isRunning = true
        message = nil
        folder = nil
        statuses = Dictionary(uniqueKeysWithValues: plan.map { ($0.id, selected.contains($0.id) ? .waiting : .skipped) })

        task = Task { [weak self] in
            // Körningarna tar timmar. Datorn får inte somna under tiden.
            let activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .idleSystemSleepDisabled],
                reason: "Testlabbet kör transkriberingar"
            )
            await self?.run(runs, source: source, transcriber: queue.transcriber)
            ProcessInfo.processInfo.endActivity(activity)
            queue.release()
            self?.isRunning = false
            self?.stepText = ""
            self?.task = nil
        }
    }

    func cancel() {
        task?.cancel()
    }

    // MARK: - Körning

    private struct Source {
        var title: String
        var createdAt: Date
        var duration: Double
        var mediaURL: URL
    }

    private func run(_ runs: [TestLabRun], source: Source, transcriber: TranscriberService) async {
        let clock = ContinuousClock()
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "okänd"
        let base = TranscriptionOptions.fromDefaults()
        let anonymization = AnonymizationSettings.options()

        do {
            let folder = try makeFolder(for: source.title)
            self.folder = folder

            stepText = "Ljudet läses in"
            let samples = try await AudioLoader.loadSamples(from: source.mediaURL)
            guard !samples.isEmpty else { throw TranscriberError.emptyAudio }

            // Talarna identifieras en gång, så att alla körningar får samma talare och
            // skillnaderna bara kommer från taligenkänningen.
            var turns: [SpeakerTurn]?
            var diarizer = "av"
            if base.identifySpeakers {
                stepText = "Talarna identifieras"
                let found = try await transcriber.speakerTurns(samples: samples, options: base)
                turns = found.turns
                diarizer = "\(found.diarizer), \(Set(found.turns.map(\.speaker)).count) talare"
            }
            try Self.write(
                Self.info(source: source, runs: runs, appVersion: appVersion, diarizer: diarizer, anonymized: anonymization != nil),
                to: folder.appending(path: "info.txt")
            )

            var lines = [TestLabReport.summaryHeader]
            for (index, run) in runs.enumerated() {
                try Task.checkCancellation()
                statuses[run.id] = .running
                stepText = "Körning \(index + 1) av \(runs.count): \(run.title)"

                var options = base
                options.model = run.engine == .pianissimo ? .pianissimo : .kbLargeStrict
                options.tuning = run.tuning
                options.levelVolume = run.levelVolume
                options.carefulSeams = run.carefulSeams
                if turns != nil {
                    options.identifySpeakers = false
                    // Talarna sätts per ord, som i en vanlig transkribering med talare.
                    options.wordTimestamps = true
                }

                var report = TestLabReport(run: run, appVersion: appVersion, startedAt: Date())
                let start = clock.now
                do {
                    let output = try await transcriber.transcribe(samples: samples, options: options, speakerTurns: turns)
                    let total = Self.seconds(clock.now - start)
                    let diagnostics = output.diagnostics
                    report.seconds = .init(
                        total: total,
                        transcription: diagnostics.transcriptionSeconds,
                        gapCheck: diagnostics.gapCheckSeconds
                    )
                    report.words = output.segments.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
                    report.segments = output.segments.count
                    report.gaps = diagnostics.gaps
                    report.whisperSegments = diagnostics.whisperSegments
                    report.pianissimoConfidence = diagnostics.pianissimoConfidence

                    var segments = output.segments
                    if let anonymization {
                        segments = Anonymizer.anonymize(segments, options: anonymization).segments
                    }
                    let metadata = TranscriptMetadata(
                        title: "\(source.title) – \(run.title)",
                        createdAt: source.createdAt,
                        duration: source.duration,
                        language: output.language,
                        model: options.modelLabel
                    )
                    try Self.write(AnalysisExporter.markdown(segments, metadata: metadata), to: folder.appending(path: "\(run.id).md"))
                    statuses[run.id] = .done(seconds: total)
                } catch {
                    if Task.isCancelled || error is CancellationError {
                        statuses[run.id] = .cancelled
                        throw CancellationError()
                    }
                    report.error = error.localizedDescription
                    statuses[run.id] = .failed(error.localizedDescription)
                }
                try Self.write(report.encoded(), to: folder.appending(path: "\(run.id).json"))
                lines.append(report.summaryLine)
                // Byte order mark, så att Excel läser åäö rätt.
                try Self.write("\u{FEFF}" + lines.joined(separator: "\n") + "\n", to: folder.appending(path: "sammanfattning.csv"))
            }
            message = "Klart. \(runs.count) körningar sparade."
        } catch {
            for (id, status) in statuses where status == .waiting || status == .running {
                statuses[id] = .cancelled
            }
            message = error is CancellationError || Task.isCancelled
                ? "Avbrutet. Det som hann bli klart finns i mappen."
                : "Testlabbet stannade: \(error.localizedDescription)"
        }
    }

    private func makeFolder(for title: String) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "sv_SE")
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        let name = String(AnalysisExporter.fileName(for: "\(formatter.string(from: Date())) \(title)").dropLast(3))
        let folder = Self.baseDirectory.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func info(source: Source, runs: [TestLabRun], appVersion: String, diarizer: String, anonymized: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "sv_SE")
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        var out = """
        Testlabb
        Inspelning: \(source.title)
        Längd: \(Int(source.duration / 60)) min
        Kördes: \(formatter.string(from: Date()))
        Appversion: \(appVersion)
        Talare: \(diarizer) (samma talare i alla körningar)
        Anonymisering: \(anonymized ? "på, som i inställningarna" : "av")

        Körningar (ändring mot en vanlig transkribering):

        """
        for run in runs {
            let change = run.differences.isEmpty ? "ingen" : run.differences.joined(separator: ", ")
            out += "\(run.id)  \(run.engine.title): \(change)\n"
        }
        return out
    }

    private static func write(_ text: String, to url: URL) throws {
        try write(Data(text.utf8), to: url)
    }

    private static func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}
