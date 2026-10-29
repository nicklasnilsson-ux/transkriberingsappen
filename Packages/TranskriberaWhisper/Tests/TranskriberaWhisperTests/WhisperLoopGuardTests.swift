import CoreML
import Foundation
import WhisperKit
import XCTest
@testable import TranskriberaWhisper

/// I 0.5.2 kunde en transkribering med ordlista stå still (t.ex. på 46 %) medan datorn
/// gick för fullt: WhisperKit avkodade samma fönster om och om igen. Se `WhisperLoopGuard`.
final class WhisperLoopGuardTests: XCTestCase {
    // Ett litet påhittat ordförråd: 0–1 text, 2 slut, 3 ledtråd, 4 start, 5 språk,
    // 6 transkribera, 7 översätt, 8 utan tidsstämplar, 9–11 tidsstämplarna 0,00–0,04.
    static let special = SpecialTokens(
        endToken: 2, englishToken: 5, noSpeechToken: 2, noTimestampsToken: 8, specialTokenBegin: 2,
        startOfPreviousToken: 3, startOfTranscriptToken: 4, timeTokenBegin: 9,
        transcribeToken: 6, translateToken: 7, whitespaceToken: 0
    )
    /// `<|startofprev|>` + ordlistan, sedan `<|startoftranscript|><|sv|><|transcribe|><|0.00|>`.
    static let promptWithVocabulary = [3, 0, 1, 4, 5, 6, 9]
    static let promptWithoutVocabulary = [4, 5, 6, 9]

    func testTimestampRulesApplyWithVocabulary() throws {
        // Modellen har skrivit en tidsstämpel; två i rad är förbjudet, och den får inte gå bakåt.
        let tokens = Self.promptWithVocabulary + [9]
        let filtered = PromptTimestampRulesFilter(specialTokens: Self.special)
            .filterLogits(try Self.logits(), withTokens: tokens)
        for timestamp in 9...11 {
            XCTAssertEqual(Self.value(filtered, timestamp), -.infinity, "Tidsstämpel \(timestamp) tillåts direkt efter <|0.00|>")
        }
        XCTAssertEqual(Self.value(filtered, 8), -.infinity, "<|notimestamps|> ska vara spärrad")
        XCTAssertGreaterThan(Self.value(filtered, 0), -.infinity, "Text ska fortfarande vara tillåten")
    }

    func testTimestampsCannotGoBackwardsWithVocabulary() throws {
        // Ett helt segment 0,00–0,02 med text, sedan får nästa tidsstämpel inte vara före 0,02.
        let tokens = Self.promptWithVocabulary + [9, 0, 11, 11, 1]
        let filtered = PromptTimestampRulesFilter(specialTokens: Self.special)
            .filterLogits(try Self.logits(), withTokens: tokens)
        XCTAssertEqual(Self.value(filtered, 9), -.infinity)
        XCTAssertEqual(Self.value(filtered, 10), -.infinity)
    }

    /// Orsaken: med ordlista hittar WhisperKits filter inte var modellens tokens börjar och
    /// släpper igenom allt. Slutar testet gå igenom efter en uppdatering har WhisperKit rättat
    /// det; skyddet kan ändå vara kvar.
    func testWhisperKitIgnoresTimestampRulesWithVocabulary() throws {
        let tokens = Self.promptWithVocabulary + [9]
        let builtIn = TimestampRulesFilter(
            specialTokens: Self.special,
            sampleBegin: Self.promptWithVocabulary.count,
            maxInitialTimestampIndex: nil,
            isModelMultilingual: true
        )
        let filtered = builtIn.filterLogits(try Self.logits(), withTokens: tokens)
        XCTAssertGreaterThan(Self.value(filtered, 9), -.infinity, "WhisperKit tillämpar nu tidsstämpelreglerna även med ordlista")
    }

    func testFilterLeavesPromptsWithoutVocabularyToWhisperKit() throws {
        let tokens = Self.promptWithoutVocabulary + [9]
        let original = try Self.logits()
        let filtered = PromptTimestampRulesFilter(specialTokens: Self.special)
            .filterLogits(try Self.logits(), withTokens: tokens)
        for index in 0..<12 {
            XCTAssertEqual(Self.value(filtered, index), Self.value(original, index))
        }
        XCTAssertEqual(PromptTimestampRulesFilter.sampleBegin(in: [3, 0, 4, 5, 6, 8], specialTokens: Self.special), nil,
                       "Utan tidsstämplar ska reglerna inte gälla")
        XCTAssertEqual(PromptTimestampRulesFilter.sampleBegin(in: Self.promptWithVocabulary + [0, 1], specialTokens: Self.special), 7)
    }

    // MARK: - Fönsterloopen

    func testSeekAlwaysMovesForward() {
        let rate = 16_000
        let window = 30 * rate
        // Står still eller går bakåt: hela fönstret hoppas över.
        XCTAssertEqual(AdvancingSegmentSeeker.advancedSeek(currentSeek: 100, proposedSeek: 100, segmentSize: window, sampleRate: rate), 100 + window)
        XCTAssertEqual(AdvancingSegmentSeeker.advancedSeek(currentSeek: 100, proposedSeek: 50, segmentSize: window, sampleRate: rate), 100 + window)
        // Knappt framåt: minst en sekund.
        XCTAssertEqual(AdvancingSegmentSeeker.advancedSeek(currentSeek: 0, proposedSeek: 320, segmentSize: window, sampleRate: rate), rate)
        // Ett kort sista fönster flyttas inte förbi sitt slut.
        XCTAssertEqual(AdvancingSegmentSeeker.advancedSeek(currentSeek: 0, proposedSeek: 10, segmentSize: 8_000, sampleRate: rate), 8_000)
        // Vanliga fall lämnas orörda.
        XCTAssertEqual(AdvancingSegmentSeeker.advancedSeek(currentSeek: 0, proposedSeek: 12 * rate, segmentSize: window, sampleRate: rate), 12 * rate)
    }

    /// Exakt det som fick fönsterloopen att snurra: `<|0.00|><|0.00|>` och sedan slut.
    /// WhisperKit står kvar på samma ställe; skyddet flyttar fram ett helt fönster.
    func testZeroLengthWindowDoesNotStall() async throws {
        let kit = try await WhisperProgressTests.tinyModel()
        let tokenizer = try XCTUnwrap(kit.tokenizer)
        let time = tokenizer.specialTokens.timeTokenBegin
        let result = DecodingResult(
            language: "sv", languageProbs: [:],
            tokens: [time, time, tokenizer.specialTokens.endToken],
            tokenLogProbs: Array(repeating: [:], count: 3),
            text: "", avgLogProb: 0, noSpeechProb: 0, temperature: 0, compressionRatio: 1
        )
        let window = 30 * WhisperKit.sampleRate
        func seek(with seeker: any SegmentSeeking) -> Int {
            seeker.findSeekPointAndSegments(
                decodingResult: result, options: DecodingOptions(), allSegmentsCount: 0,
                currentSeek: 5 * window, segmentSize: window, sampleRate: WhisperKit.sampleRate,
                timeToken: time, specialToken: tokenizer.specialTokens.specialTokenBegin, tokenizer: tokenizer
            ).0
        }
        XCTAssertEqual(seek(with: SegmentSeeker()), 5 * window, "WhisperKit flyttar nu fram även här; skyddet kan ändå vara kvar")
        let guarded = AdvancingSegmentSeeker()
        XCTAssertEqual(seek(with: guarded), 6 * window)
        XCTAssertEqual(guarded.forcedAdvances, 1)
    }

    func testInstallIsIdempotent() async throws {
        let kit = try await WhisperProgressTests.tinyModel()
        WhisperLoopGuard.install(on: kit)
        WhisperLoopGuard.install(on: kit)
        XCTAssertTrue(kit.segmentSeeker is AdvancingSegmentSeeker)
        XCTAssertEqual((kit.textDecoder.logitsFilters ?? []).filter { $0 is PromptTimestampRulesFilter }.count, 1)
    }

    /// Hela vägen med ordlista, som i appen: transkriberingen ska bli klar inom rimlig tid,
    /// förloppet nå 100 % och inga segment får sluta före de börjar.
    func testTranscriptionWithVocabularyFinishes() async throws {
        let audio = try WhisperProgressTests.spokenAudio(minimumSeconds: 75)
        let kit = try await WhisperProgressTests.tinyModel()
        var options = WhisperProgressTests.options
        options.wordTimestamps = true
        options.promptTokens = kit.tokenizer?.encode(text: " Fortnox, bruttovinst, progress bar.")
            .filter { $0 < (kit.tokenizer?.specialTokens.specialTokenBegin ?? 0) }
        XCTAssertFalse(options.promptTokens?.isEmpty ?? true)
        let decodeOptions = options

        let recorder = ProgressRecorder()
        let results = try await Self.withTimeout(seconds: 600) {
            try await WhisperProgress.transcribe(
                kit: kit, audioArray: audio, decodeOptions: decodeOptions,
                onProgress: { recorder.add($0) }, onText: { _ in }
            )
        }
        let segments = results.flatMap(\.segments)
        XCTAssertFalse(segments.isEmpty, "Modellen hittade ingen text")
        XCTAssertEqual(recorder.values.last, 1, "Förloppet når inte 100 %")
        for segment in segments {
            XCTAssertGreaterThanOrEqual(segment.end, segment.start, "Segment som slutar före det börjar: \(segment.text)")
        }
    }

    // MARK: - Hjälp

    static func logits() throws -> MLMultiArray {
        let array = try MLMultiArray(shape: [1, 1, 12], dataType: .float16)
        for index in 0..<12 { array[[0, 0, index] as [NSNumber]] = NSNumber(value: 0.1 * Double(index + 1)) }
        return array
    }

    static func value(_ array: MLMultiArray, _ index: Int) -> Float {
        array[[0, 0, index] as [NSNumber]].floatValue
    }

    struct Timeout: Error, CustomStringConvertible {
        let seconds: Double
        var description: String { "Blev inte klar inom \(Int(seconds)) s: fönsterloopen har troligen fastnat" }
    }

    static func withTimeout<T: Sendable>(seconds: Double, _ work: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw Timeout(seconds: seconds)
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [Double] = []
    var values: [Double] { lock.withLock { _values } }
    func add(_ value: Double) { lock.withLock { _values.append(value) } }
}
