import XCTest
@testable import TranskriberaCore

/// Påhittade meningar (riktiga intervjuer får aldrig bli testdata).
final class FacitComparisonTests: XCTestCase {
    private func words(_ text: String, from start: Double = 0) -> [WordTimingData] {
        text.split(separator: " ").enumerated().map { index, word in
            WordTimingData(word: " " + word, start: start + Double(index) * 0.1, end: start + Double(index + 1) * 0.1, probability: 1)
        }
    }

    private func segment(_ text: String, from start: Double = 0) -> SegmentData {
        let w = words(text, from: start)
        return SegmentData(start: w[0].start, end: w[w.count - 1].end, text: text, speaker: "Talare 1", words: w)
    }

    func testFacitHeadersAreSkipped() {
        let facit = "Talare 2 - 0:04\nHej på dig.\n\nTalare 1 - 1:02:03\nHej."
        XCTAssertEqual(FacitComparison.facitWords(facit), ["Hej", "på", "dig.", "Hej."])
        XCTAssertFalse(FacitComparison.isHeader("Vi pratade om det - 3 gånger"))
    }

    func testMissingNotIsAMeaningError() {
        let result = FacitComparison.compare([segment("Så man ska bara skriva saker.", from: 30)],
                                             facit: "Talare 1 - 0:30\nSå man ska inte bara skriva saker.")
        XCTAssertEqual(result.meaningErrors.count, 1)
        XCTAssertEqual(result.meaningErrors.first?.facit, "inte")
        XCTAssertEqual(result.meaningErrors.first?.heard, "")
        XCTAssertEqual(result.wordMatch, 6.0 / 7.0, accuracy: 0.001)
        XCTAssertEqual(result.marks, [])
        XCTAssertEqual(result.missed.count, 1, "Utan markeringar är alla innebördsfel omarkerade")
    }

    func testInflectionsAndFillersAreNotMeaningErrors() {
        let result = FacitComparison.compare([segment("Vi går igenom fakturan sen.")], facit: "Eh, vi går igenom fakturorna sen.")
        XCTAssertEqual(result.meaningErrors, [])
        XCTAssertEqual(result.words, 5)
        XCTAssertEqual(result.facitWords, 5, "\"Eh\" räknas inte")
    }

    func testMarksAreJudgedAgainstFacit() {
        // KB Large hörde "inte" (rätt enligt facit) och "behöver" (fel enligt facit).
        let mine = [segment("Så man ska bara skriva saker. Vi vill gå nu.")]
        let (marked, count) = CrossCheck.mark(mine, against: words("Så man ska inte bara skriva saker. Vi behöver gå nu."))
        XCTAssertEqual(count, 2)
        let result = FacitComparison.compare(marked, facit: "Så man ska inte bara skriva saker. Vi vill gå nu.")
        XCTAssertEqual(result.marks.map(\.mark.heard), ["bara", "vill"])
        XCTAssertEqual(result.marks.map(\.isError), [true, false])
        XCTAssertEqual(result.marks.map(\.facit), ["inte bara", "vill"])
        XCTAssertEqual(result.meaningErrors.count, 1)
        XCTAssertEqual(result.caught, 1)
        XCTAssertEqual(result.missed, [])
        let line = FacitComparison.summaryLine(result, title: "Test", minutes: 30)
        XCTAssertTrue(line.contains("2 markeringar (4 per timme), varav 1 riktiga fel, 1 av 1 innebördsfel markerade"), line)
        let report = FacitComparison.report(result, title: "Test", facitName: "klang.txt", minutes: 30)
        XCTAssertTrue(report.contains("FEL   …Så man ska [bara] skriva saker."), report)
        XCTAssertTrue(report.contains("RÄTT  …"), report)
    }

    func testTextWithoutWordTimingsIsCompared() {
        let plain = SegmentData(start: 5, end: 8, text: "Det går nog bra.", speaker: nil, words: [])
        let result = FacitComparison.compare([plain], facit: "Det går inte bra.")
        XCTAssertEqual(result.words, 4)
        XCTAssertEqual(result.meaningErrors.map(\.heard), ["nog"])
        XCTAssertEqual(result.meaningErrors.first?.time, 5)
    }

    func testReportIsAnonymized() {
        let result = FacitComparison.compare([segment("Anna ska inte gå.")], facit: "Anna ska gå.")
        let report = FacitComparison.report(result, title: "Test", facitName: "f.txt", minutes: 1,
                                            anonymize: { $0.replacingOccurrences(of: "Anna", with: "[Namn]") })
        XCTAssertFalse(report.contains("Anna"))
        XCTAssertTrue(report.contains("[Namn]"))
    }
}
