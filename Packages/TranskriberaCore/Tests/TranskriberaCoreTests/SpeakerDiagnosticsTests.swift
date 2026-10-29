import XCTest
@testable import TranskriberaCore

final class SpeakerDiagnosticsTests: XCTestCase {
    private let segments = [
        SegmentData(
            start: 0, end: 2.004, text: "hemligt kundnamn Svensson", speaker: "Talare 1",
            words: [
                WordTimingData(word: "hemligt", start: 0, end: 0.5, probability: 1),
                WordTimingData(word: "Svensson", start: 0.5, end: 1.2345, probability: 1),
            ],
            uncertainSpeaker: true
        )
    ]
    private let turns = [SpeakerTurn(start: 1, end: 3, speaker: 1), SpeakerTurn(start: 0, end: 1, speaker: 0)]

    func testFileHasNoWordsFromTheConversation() throws {
        let diagnostics = SpeakerDiagnostics(diarizer: "test", speakers: "2 talare", turns: turns, segments: segments)
        let json = try XCTUnwrap(String(data: diagnostics.encoded(), encoding: .utf8))
        for secret in ["hemligt", "kundnamn", "Svensson"] {
            XCTAssertFalse(json.contains(secret), "\(secret) hamnade i felsökningsfilen")
        }
    }

    func testTurnsAndWordTimesSurviveAndAreRounded() throws {
        let diagnostics = SpeakerDiagnostics(diarizer: "test", speakers: "2 talare", turns: turns, segments: segments)
        XCTAssertEqual(diagnostics.turns.map(\.start), [0, 1])
        XCTAssertEqual(diagnostics.pieces[0].end, 2)
        XCTAssertEqual(diagnostics.pieces[0].words, [[0, 0.5], [0.5, 1.23]])
        XCTAssertTrue(diagnostics.pieces[0].uncertain)
        let decoded = try JSONDecoder().decode(SpeakerDiagnostics.self, from: diagnostics.encoded())
        XCTAssertEqual(decoded, diagnostics)
    }
}
