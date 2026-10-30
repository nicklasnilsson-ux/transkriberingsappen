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
}
