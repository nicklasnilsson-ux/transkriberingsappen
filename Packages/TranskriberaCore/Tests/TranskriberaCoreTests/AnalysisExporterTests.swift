import XCTest
@testable import TranskriberaCore

final class AnalysisExporterTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let metadata = TranscriptMetadata(
        title: "Test 3 – P05",
        createdAt: Date(timeIntervalSince1970: 1_793_000_000),
        duration: 125,
        language: "Svenska"
    )

    func testOneTimestampPerSpeakerChange() {
        let segments = [
            SegmentData(start: 0, end: 2, text: " Hur hittade du knappen?", speaker: "Moderator"),
            SegmentData(start: 2.5, end: 4, text: "Var började du leta?", speaker: "Moderator"),
            SegmentData(start: 65, end: 70, text: "Jag letade i menyn först.", speaker: "Deltagare"),
            SegmentData(start: 70, end: 72, text: "Sen gav jag upp.", speaker: "Deltagare"),
            SegmentData(start: 73, end: 74, text: "Okej.", speaker: "Moderator")
        ]
        let output = AnalysisExporter.markdown(segments, metadata: metadata, timeZone: utc)
        XCTAssertEqual(output, """
        # Test 3 – P05

        - Datum: 2026-10-26 07:33
        - Längd: 2 min 05 s
        - Talare: Moderator, Deltagare
        - Språk: Svenska

        ---

        [00:00] **Moderator:** Hur hittade du knappen? Var började du leta?

        [01:05] **Deltagare:** Jag letade i menyn först. Sen gav jag upp.

        [01:13] **Moderator:** Okej.

        """)
    }

    func testWithoutSpeakersBreaksOnPauses() {
        let segments = [
            SegmentData(start: 0, end: 2, text: "Första."),
            SegmentData(start: 2.2, end: 4, text: "Andra."),
            SegmentData(start: 10, end: 12, text: "Efter paus."),
            SegmentData(start: 12, end: 13, text: "  ")
        ]
        let paragraphs = AnalysisExporter.paragraphs(segments.filter { !$0.text.trimmed.isEmpty })
        XCTAssertEqual(paragraphs, [
            .init(start: 0, speaker: nil, text: "Första. Andra."),
            .init(start: 10, speaker: nil, text: "Efter paus.")
        ])
        let output = AnalysisExporter.markdown(segments, metadata: metadata, timeZone: utc)
        XCTAssertFalse(output.contains("Talare:"))
        XCTAssertTrue(output.hasSuffix("[00:10] Efter paus.\n"))
    }

    func testWithoutSpeakersCapsParagraphLength() {
        let segments = (0..<8).map { SegmentData(start: Double($0), end: Double($0) + 1, text: "S\($0).") }
        let paragraphs = AnalysisExporter.paragraphs(segments)
        XCTAssertEqual(paragraphs.count, 2)
        XCTAssertEqual(paragraphs[1].start, 6)
    }

    func testFileNames() {
        XCTAssertEqual(AnalysisExporter.fileName(for: "Test 1: P01/P02"), "Test 1- P01-P02.md")
        XCTAssertEqual(AnalysisExporter.fileName(for: "  "), "Transkribering.md")
        XCTAssertEqual(
            AnalysisExporter.uniqueFileNames(for: ["Intervju", "intervju", "Intervju", "Annan"]),
            ["Intervju.md", "intervju 2.md", "Intervju 3.md", "Annan.md"]
        )
    }
}
