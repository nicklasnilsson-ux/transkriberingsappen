import Foundation
import WhisperKit
import XCTest
@testable import TranskriberaWhisper

/// Kör en riktig (liten) Whisper-modell på tal som är längre än 30 sekunder, så att
/// WhisperKit delar upp ljudet med VAD precis som i appen. Där stod förloppet på 0 %
/// i 0.5.1, eftersom WhisperKit inte skickade vidare vår förloppsfunktion.
final class WhisperProgressTests: XCTestCase {
    func testProgressMovesAndTextArrivesForLongAudio() async throws {
        let audio = try Self.spokenAudio(minimumSeconds: 75)
        XCTAssertGreaterThan(Double(audio.count) / Double(WhisperKit.sampleRate), 30, "Ljudet måste delas upp för att testet ska gälla")

        let kit = try await Self.tinyModel()

        let recorder = Recorder()
        let results = try await WhisperProgress.transcribe(
            kit: kit,
            audioArray: audio,
            decodeOptions: Self.options,
            onProgress: { recorder.add(progress: $0) },
            onText: { recorder.add(text: $0) }
        )

        let progress = recorder.progress
        XCTAssertFalse(results.flatMap(\.segments).isEmpty, "Modellen hittade ingen text")
        XCTAssertTrue(progress.contains { $0 > 0 && $0 < 1 }, "Inget förlopp under transkriberingen: \(progress)")
        XCTAssertEqual(progress.last, 1, "Förloppet når inte 100 %: \(progress)")
        XCTAssertEqual(progress, progress.sorted(), "Förloppet gick bakåt: \(progress)")
        XCTAssertFalse(recorder.texts.isEmpty, "Ingen löpande text under transkriberingen")
        XCTAssertNil(kit.segmentDiscoveryCallback, "Textfunktionen ska tas bort efteråt")
    }

    /// Orsaken till felet i 0.5.1: med VAD-uppdelning anropas aldrig `segmentCallback`
    /// som skickas till `transcribe`. Slutar det här testet att gå igenom efter en
    /// uppdatering av WhisperKit har de rättat det, och testet kan tas bort.
    func testWhisperKitIgnoresSegmentCallbackWithVAD() async throws {
        let audio = try Self.spokenAudio(minimumSeconds: 75)
        let kit = try await Self.tinyModel()
        let recorder = Recorder()
        _ = try await kit.transcribe(
            audioArray: audio,
            decodeOptions: Self.options,
            segmentCallback: { segments in
                if let text = segments.last?.text { recorder.add(text: text) }
            }
        )
        XCTAssertTrue(recorder.texts.isEmpty, "WhisperKit anropar nu segmentCallback även med VAD")
    }

    func testTrackerNeverGoesBackwards() {
        let tracker = ProgressTracker()
        var reported: [Double] = []
        let fractions: [Double] = [0, 0.4, 0.2, 0.4, Double.nan, 0.4005, 1.5, 1]
        for fraction in fractions {
            tracker.advance(to: fraction) { reported.append($0) }
        }
        XCTAssertEqual(reported, [0.4, 1])
    }

    // MARK: - Hjälp

    static let modelsDirectory = FileManager.default.temporaryDirectory
        .appending(path: "TranskriberaWhisperTests", directoryHint: .isDirectory)

    static let options = DecodingOptions(
        task: .transcribe,
        language: "en",
        usePrefillPrompt: true,
        skipSpecialTokens: true,
        withoutTimestamps: false,
        // Appen kör upp till 16 delar samtidigt. Med två åt gången hinner förloppet
        // garanterat röra sig medan resten avkodas, så testet blir inte slumpmässigt.
        concurrentWorkerCount: 2,
        chunkingStrategy: .vad
    )

    static func tinyModel() async throws -> WhisperKit {
        try await WhisperKit(WhisperKitConfig(
            model: "tiny",
            downloadBase: modelsDirectory,
            verbose: false,
            logLevel: .error,
            prewarm: false,
            load: true,
            download: true
        ))
    }

    /// Talat ljud från macOS talsyntes (`say`), 16 kHz mono.
    static func spokenAudio(minimumSeconds: Double) throws -> [Float] {
        let sentence = "This is a test of the progress bar. The transcription should move forward while the model works through the recording. "
        let text = String(repeating: sentence, count: 12)
        let file = modelsDirectory.appending(path: "speech.wav")
        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: file)

        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-r", "160", "--file-format=WAVE", "--data-format=LEI16@16000", "-o", file.path, text]
        try say.run()
        say.waitUntilExit()
        XCTAssertEqual(say.terminationStatus, 0, "say misslyckades")

        let audio = try AudioProcessor.loadAudioAsFloatArray(fromPath: file.path)
        let seconds = Double(audio.count) / Double(WhisperKit.sampleRate)
        guard seconds >= minimumSeconds else {
            throw NSError(domain: "WhisperProgressTests", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Talsyntesen gav bara \(Int(seconds)) s ljud, behöver \(Int(minimumSeconds)) s"
            ])
        }
        return audio
    }
}

private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _progress: [Double] = []
    private var _texts: [String] = []

    var progress: [Double] { lock.withLock { _progress } }
    var texts: [String] { lock.withLock { _texts } }

    func add(progress: Double) { lock.withLock { _progress.append(progress) } }
    func add(text: String) { lock.withLock { _texts.append(text) } }
}
