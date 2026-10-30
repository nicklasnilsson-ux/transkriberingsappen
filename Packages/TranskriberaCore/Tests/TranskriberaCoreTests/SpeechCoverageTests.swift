import XCTest
@testable import TranskriberaCore

final class SpeechCoverageTests: XCTestCase {
    let rate = 16_000.0

    /// Ton (som "tal") och tystnad med lite brus, i sekunder.
    func audio(_ parts: [(seconds: Double, speech: Bool)]) -> [Float] {
        var samples: [Float] = []
        var generator = SystemRandomNumberGenerator()
        for part in parts {
            for index in 0..<Int(part.seconds * rate) {
                let noise = Float.random(in: -0.002...0.002, using: &generator)
                let tone = part.speech ? 0.3 * Float(sin(2 * Double.pi * 220 * Double(index) / rate)) : 0
                samples.append(tone + noise)
            }
        }
        return samples
    }

    func testSpeechRegionsFollowTheSound() {
        let samples = audio([(1, false), (3, true), (2, false), (4, true), (1, false)])
        let regions = SpeechCoverage.speechRegions(in: samples, sampleRate: rate)
        XCTAssertEqual(regions.count, 2)
        XCTAssertEqual(regions[0].start, 1, accuracy: 0.1)
        XCTAssertEqual(regions[0].end, 4, accuracy: 0.1)
        XCTAssertEqual(regions[1].start, 6, accuracy: 0.1)
        XCTAssertEqual(regions[1].end, 10, accuracy: 0.1)
    }

    func testSilenceHasNoSpeech() {
        XCTAssertEqual(SpeechCoverage.speechRegions(in: audio([(5, false)]), sampleRate: rate), [])
    }

    /// Felet från intervjun med KB-Whisper: ett helt parti tal saknade text.
    func testSpeechWithoutTextIsFound() {
        let speech = [TimeRange(start: 0, end: 20), TimeRange(start: 22, end: 60)]
        let segments = [
            SegmentData(start: 0, end: 19.8, text: "Början."),
            SegmentData(start: 22.1, end: 30, text: "Sedan."),
            // 30–52 saknas
            SegmentData(start: 52, end: 60, text: "Slutet.")
        ]
        let gaps = SpeechCoverage.uncovered(speech: speech, segments: segments)
        XCTAssertEqual(gaps.count, 1)
        XCTAssertEqual(gaps[0].start, 30.3, accuracy: 0.01)
        XCTAssertEqual(gaps[0].end, 51.7, accuracy: 0.01)
    }

    func testFullyCoveredSpeechHasNoGaps() {
        let speech = [TimeRange(start: 0, end: 10)]
        let segments = [SegmentData(start: 0.2, end: 4, text: "Ett."), SegmentData(start: 4.1, end: 9.9, text: "Två.")]
        XCTAssertEqual(SpeechCoverage.uncovered(speech: speech, segments: segments), [])
    }

    func testShortGapsAreIgnored() {
        let speech = [TimeRange(start: 0, end: 10)]
        let segments = [SegmentData(start: 0, end: 4, text: "Ett."), SegmentData(start: 5.5, end: 10, text: "Två.")]
        XCTAssertEqual(SpeechCoverage.uncovered(speech: speech, segments: segments), [])
    }

    func testShiftedMovesSegmentAndWords() {
        let segment = SegmentData(start: 1, end: 2, text: "Hej.", words: [WordTimingData(word: " Hej.", start: 1, end: 2, probability: 1)])
        let moved = segment.shifted(by: 30)
        XCTAssertEqual(moved.start, 31)
        XCTAssertEqual(moved.words[0].end, 32)
    }

    /// Påhittade tider: den andra taligenkännaren hör ett parti som den första saknar. Ett
    /// ensamt kort "mm" (här vid 5 sekunder, redan täckt) räknas inte som lucka.
    func testGapsFromAReferenceRecognizerAreFilled() {
        let segments = [
            SegmentData(start: 0, end: 10, text: "Början."),
            SegmentData(start: 30, end: 40, text: "Slutet.")
        ]
        let reference = [
            SegmentData(start: 0, end: 10, text: "Början."),
            SegmentData(start: 11, end: 11.8, text: "Mm."),
            SegmentData(start: 12, end: 18, text: "Ett parti"),
            SegmentData(start: 18.2, end: 25, text: "som saknades."),
            SegmentData(start: 30, end: 40, text: "Slutet.")
        ]
        let gaps = SpeechCoverage.missing(from: reference, in: segments)
        XCTAssertEqual(gaps.count, 1)
        XCTAssertEqual(gaps[0].start, 11, accuracy: 0.2)
        XCTAssertEqual(gaps[0].end, 25, accuracy: 0.2)

        let filled = SpeechCoverage.fill(segments, with: reference, gaps: gaps)
        XCTAssertEqual(filled.map(\.text), ["Början.", "Mm.", "Ett parti", "som saknades.", "Slutet."])
    }

    func testNoGapWhenTheReferenceHasNothingExtra() {
        let segments = [SegmentData(start: 0, end: 10, text: "Hej.")]
        XCTAssertEqual(SpeechCoverage.missing(from: segments, in: segments), [])
    }

    /// Påhittade tider: luckan täcker bara slutet av en lång mening hos den andra
    /// taligenkännaren. Bara orden i luckan läggs till, inte hela meningen.
    func testOnlyWordsInsideTheGapAreFilled() {
        let words = (0..<10).map { WordTimingData(word: " ord\($0)", start: Double($0), end: Double($0) + 0.9, probability: 1) }
        let reference = [SegmentData(start: 0, end: 9.9, text: "ord0 ord1 ord2 ord3 ord4 ord5 ord6 ord7 ord8 ord9", words: words)]
        let existing = [SegmentData(start: 0, end: 5.9, text: "ord0 ord1 ord2 ord3 ord4 ord5")]

        let filled = SpeechCoverage.fill(existing, with: reference, gaps: [TimeRange(start: 6, end: 10)])
        XCTAssertEqual(filled.map(\.text), ["ord0 ord1 ord2 ord3 ord4 ord5", "ord6 ord7 ord8 ord9"])
        XCTAssertEqual(filled[1].start, 6, accuracy: 0.001)
        XCTAssertEqual(filled[1].words.count, 4)
    }

    /// Ord i två skilda luckor blir två segment, inte ett som spänner över texten emellan.
    func testWordsInSeparateGapsBecomeSeparateSegments() {
        let words = (0..<6).map { WordTimingData(word: " ord\($0)", start: Double($0), end: Double($0) + 0.9, probability: 1) }
        let reference = [SegmentData(start: 0, end: 5.9, text: "ord0 ord1 ord2 ord3 ord4 ord5", words: words)]
        let filled = SpeechCoverage.fill([], with: reference, gaps: [TimeRange(start: 0, end: 1.9), TimeRange(start: 4, end: 6)])
        XCTAssertEqual(filled.map(\.text), ["ord0 ord1", "ord4 ord5"])
    }

    /// Den andra taligenkännarens tal läggs till ljudnivåns: luckor som bara någon av dem
    /// ser ska båda hittas.
    func testCombinedSpeechKeepsGapsFromBothSources() {
        let energy = [TimeRange(start: 0, end: 5), TimeRange(start: 20, end: 26)]
        let reference = [TimeRange(start: 10, end: 14), TimeRange(start: 21, end: 25)]
        let combined = SpeechCoverage.combine(energy, reference)
        XCTAssertEqual(combined, [TimeRange(start: 0, end: 5), TimeRange(start: 10, end: 14), TimeRange(start: 20, end: 26)])

        let gaps = SpeechCoverage.uncovered(speech: combined, segments: [])
        XCTAssertEqual(gaps.count, 3)
    }
}
