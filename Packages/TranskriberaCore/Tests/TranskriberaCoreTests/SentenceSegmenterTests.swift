import XCTest
@testable import TranskriberaCore

final class SentenceSegmenterTests: XCTestCase {
    func words(_ text: String, start: Double = 0, step: Double = 0.3) -> [WordTimingData] {
        text.split(separator: " ").enumerated().map { index, word in
            let begin = start + Double(index) * step
            return WordTimingData(word: " " + word, start: begin, end: begin + step * 0.9, probability: 1)
        }
    }

    func testSplitsAtSentenceEnds() {
        let result = SentenceSegmenter.segments(from: words("Hur ofta är ni inne? Varje dag. Bra."))
        XCTAssertEqual(result.map(\.text), ["Hur ofta är ni inne?", "Varje dag.", "Bra."])
        XCTAssertEqual(result[1].words.count, 2)
        XCTAssertEqual(result[0].start, 0)
    }

    func testSplitsAtPauses() {
        let first = words("vi har inget bra")
        let second = words("system för det", start: 5)
        let result = SentenceSegmenter.segments(from: first + second)
        XCTAssertEqual(result.map(\.text), ["vi har inget bra", "system för det"])
    }

    func testLongRunsAreSplit() {
        let text = (0..<50).map { "ord\($0)" }.joined(separator: " ")
        let result = SentenceSegmenter.segments(from: words(text))
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].words.count, SentenceSegmenter.hardMaxWords)
        XCTAssertEqual(result.flatMap(\.words).count, 50)
    }

    func testEmptyInput() {
        XCTAssertEqual(SentenceSegmenter.segments(from: []), [])
    }
}
