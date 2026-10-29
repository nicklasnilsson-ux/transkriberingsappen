import XCTest
@testable import TranskriberaCore

final class TimeFormattingTests: XCTestCase {
    func testShort() {
        XCTAssertEqual(TimeFormatting.short(0), "00:00")
        XCTAssertEqual(TimeFormatting.short(83.9), "01:23")
        XCTAssertEqual(TimeFormatting.short(3723), "1:02:03")
    }

    func testSubtitleClocks() {
        XCTAssertEqual(TimeFormatting.srt(83.456), "00:01:23,456")
        XCTAssertEqual(TimeFormatting.vtt(3723.5), "01:02:03.500")
        XCTAssertEqual(TimeFormatting.srt(-1), "00:00:00,000")
    }
}

final class TextCleaningTests: XCTestCase {
    func testRemovesSpecialTokens() {
        XCTAssertEqual(TextCleaning.clean("<|startoftranscript|><|sv|> Hej  på dig <|0.00|>"), "Hej på dig")
    }

    /// Läckte i en riktig transkribering med KB Medium ordagrann.
    func testRemovesBrokenSpecialTokens() {
        XCTAssertEqual(TextCleaning.clean("Vi säljer |mospeech|> ungefär det."), "Vi säljer ungefär det.")
        XCTAssertEqual(TextCleaning.clean("Ja &lt;|nospeech|&gt; precis."), "Ja precis.")
        XCTAssertEqual(TextCleaning.clean("A | B"), "A | B")
    }

    func testNonSpeechMarker() {
        XCTAssertTrue(TextCleaning.isNonSpeechMarker("[Musik]"))
        XCTAssertTrue(TextCleaning.isNonSpeechMarker("  "))
        XCTAssertFalse(TextCleaning.isNonSpeechMarker("Hej [skratt] där"))
    }
}

final class TextSearchTests: XCTestCase {
    func testCaseInsensitive() {
        XCTAssertTrue(TextSearch.matches("Mötet började", query: "MÖTET"))
        XCTAssertTrue(TextSearch.matches("vad som helst", query: "  "))
    }

    func testRanges() {
        let text = "Hej hej HEJ"
        XCTAssertEqual(TextSearch.ranges(of: "hej", in: text).count, 3)
        XCTAssertEqual(TextSearch.countMatches(of: "hej", in: [text, "inget"]), 3)
    }
}

final class ExporterTests: XCTestCase {
    let metadata = TranscriptMetadata(
        title: "Möte",
        createdAt: Date(timeIntervalSince1970: 0),
        duration: 10,
        language: "sv",
        model: "tiny"
    )

    let segments = [
        SegmentData(start: 0, end: 2.5, text: " Hej allihop.", speaker: "Talare 1"),
        SegmentData(start: 2.5, end: 5, text: " Välkomna.", speaker: "Talare 1"),
        SegmentData(start: 5, end: 9, text: " Tack!", speaker: "Talare 2"),
        SegmentData(start: 9, end: 10, text: "   ")
    ]

    func testSRT() {
        let srt = TranscriptExporter.export(segments, metadata: metadata, format: .srt)
        XCTAssertEqual(srt, """
        1
        00:00:00,000 --> 00:00:02,500
        Talare 1: Hej allihop.

        2
        00:00:02,500 --> 00:00:05,000
        Talare 1: Välkomna.

        3
        00:00:05,000 --> 00:00:09,000
        Talare 2: Tack!

        """)
    }

    func testVTTHeaderAndVoiceTags() {
        let vtt = TranscriptExporter.export(segments, metadata: metadata, format: .vtt)
        XCTAssertTrue(vtt.hasPrefix("WEBVTT\n\n00:00:00.000 --> 00:00:02.500\n<v Talare 1>Hej allihop.\n"))
    }

    func testPlainTextGroupsBySpeaker() {
        let text = TranscriptExporter.export(
            segments, metadata: metadata, format: .plainText,
            options: ExportOptions(includeTimestamps: false)
        )
        XCTAssertEqual(text, "Talare 1: Hej allihop. Välkomna.\n\nTalare 2: Tack!\n")
    }

    func testPlainTextWithTimestamps() {
        let text = TranscriptExporter.export(segments, metadata: metadata, format: .plainText)
        XCTAssertTrue(text.hasPrefix("[00:00] Talare 1: Hej allihop.\n[00:02] Talare 1: Välkomna.\n"))
    }

    func testJSONRoundTrip() throws {
        let json = TranscriptExporter.export(segments, metadata: metadata, format: .json)
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        XCTAssertEqual(object?["title"] as? String, "Möte")
        XCTAssertEqual((object?["segments"] as? [Any])?.count, 3)
    }

    func testLongSegmentsAreSplitUsingWords() {
        let words = (0..<30).map { i in
            WordTimingData(word: " ord\(i)", start: Double(i), end: Double(i) + 0.9, probability: 1)
        }
        let long = SegmentData(start: 0, end: 30, text: words.map(\.word).joined(), words: words)
        let cues = TranscriptExporter.subtitleCues([long], options: ExportOptions(maxSubtitleCharacters: 40))
        XCTAssertGreaterThan(cues.count, 1)
        XCTAssertTrue(cues.allSatisfy { $0.text.count <= 40 })
        XCTAssertEqual(cues.first?.start, 0)
        XCTAssertEqual(cues.last?.end, 29.9)
    }
}
