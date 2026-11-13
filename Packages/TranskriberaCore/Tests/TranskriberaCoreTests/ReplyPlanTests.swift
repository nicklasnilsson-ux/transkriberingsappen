import XCTest
@testable import TranskriberaCore

final class ReplyPlanTests: XCTestCase {
    private func turn(_ start: Double, _ end: Double, _ speaker: Int) -> SpeakerTurn {
        SpeakerTurn(start: start, end: end, speaker: speaker)
    }

    private func word(_ text: String, _ start: Double, _ end: Double) -> WordTimingData {
        WordTimingData(word: text, start: start, end: end, probability: 1)
    }

    private func assertPieces(
        _ pieces: [ReplyPiece],
        _ expected: [(Double, Double, Int?, Bool)],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(pieces.count, expected.count, "\(pieces)", file: file, line: line)
        for (piece, (start, end, speaker, overlapped)) in zip(pieces, expected) {
            XCTAssertEqual(piece.start, start, accuracy: 1e-9, file: file, line: line)
            XCTAssertEqual(piece.end, end, accuracy: 1e-9, file: file, line: line)
            XCTAssertEqual(piece.speaker, speaker, file: file, line: line)
            XCTAssertEqual(piece.overlapped, overlapped, file: file, line: line)
        }
    }

    /// Mötet 2026-11-12: korta svar direkt efter en fråga försvann i grannens replik.
    func testShortAnswerRightAfterQuestionGetsItsOwnPiece() {
        let pieces = ReplyPlan.pieces(turns: [turn(0, 5, 0), turn(4.9, 5.6, 1), turn(6, 10, 0)], duration: 10)
        assertPieces(pieces, [(0, 4.9, 0, false), (4.9, 5.8, 1, true), (5.8, 10, 0, false)])
    }

    /// Ett "Mm" mitt i någon annans monolog ska inte klippa monologen eller göra den osäker.
    func testBackchannelInsideMonologueDoesNotSplitIt() {
        let pieces = ReplyPlan.pieces(turns: [turn(0, 10, 0), turn(4, 4.4, 1)], duration: 10)
        assertPieces(pieces, [(0, 10, 0, false)])
    }

    func testShortSilenceInsideOneSpeakersReplyIsBridged() {
        let pieces = ReplyPlan.pieces(turns: [turn(0, 2, 0), turn(2.6, 4, 0)], duration: 4)
        assertPieces(pieces, [(0, 4, 0, false)])
    }

    /// Långa luckor utan talare transkriberas ändå, så att inget tal tappas.
    func testLongGapWithoutSpeakerIsKept() {
        let pieces = ReplyPlan.pieces(turns: [turn(0, 2, 0), turn(5, 6, 1)], duration: 6)
        assertPieces(pieces, [(0, 2, 0, false), (2, 5, nil, false), (5, 6, 1, false)])
    }

    func testNoTurnsGivesOnePieceWithoutSpeaker() {
        assertPieces(ReplyPlan.pieces(turns: [], duration: 3), [(0, 3, nil, false)])
        XCTAssertEqual(ReplyPlan.pieces(turns: [], duration: 0), [])
    }

    func testShortLeadingSilenceGoesToTheFirstReply() {
        assertPieces(ReplyPlan.pieces(turns: [turn(0.3, 2, 0)], duration: 2), [(0, 2, 0, false)])
    }

    func testTinyOverlapSliverGoesToTheLongerNeighbourAndIsMarked() {
        let pieces = ReplyPlan.pieces(turns: [turn(0, 3, 0), turn(2.95, 3.05, 1), turn(3.05, 6, 2)], duration: 6)
        assertPieces(pieces, [(0, 3.05, 0, true), (3.05, 6, 2, false)])
    }

    /// Bitarna täcker alltid hela ljudet utan glapp, oavsett hur turerna ser ut.
    func testPiecesCoverTheWholeAudioWithoutGaps() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            let duration = Double.random(in: 1...120, using: &generator)
            let turns = (0..<Int.random(in: 0...30, using: &generator)).map { _ in
                let start = Double.random(in: -1...duration, using: &generator)
                return turn(start, start + Double.random(in: 0...8, using: &generator), Int.random(in: 0...3, using: &generator))
            }
            let pieces = ReplyPlan.pieces(turns: turns, duration: duration)
            XCTAssertEqual(pieces.first?.start ?? -1, 0, accuracy: 1e-9)
            XCTAssertEqual(pieces.last?.end ?? -1, duration, accuracy: 1e-9)
            for (previous, next) in zip(pieces, pieces.dropFirst()) {
                XCTAssertEqual(previous.end, next.start, accuracy: 1e-9)
                XCTAssertNotEqual(previous.speaker, next.speaker)
            }
            XCTAssertTrue(pieces.allSatisfy { $0.end > $0.start })
        }
    }

    func testSegmentsKeepEachPiecesSpeakerAndNumberInOrderOfAppearance() {
        let pieces = [
            ReplyPiece(start: 0, end: 2, speaker: 3),
            ReplyPiece(start: 2, end: 5, speaker: nil),
            ReplyPiece(start: 5, end: 6, speaker: 1)
        ]
        let words = [
            [word(" Hej.", 0.1, 0.5), word(" Utanför.", 2.5, 2.9)],
            [word(" eh", 3.0, 3.2), word(" ja", 3.2, 3.4)],
            [word(" Ja.", 5.1, 5.4)]
        ]
        let result = ReplyPlan.segments(pieces: pieces, words: words, turns: [turn(0, 2, 3), turn(5, 6, 1)])
        XCTAssertEqual(result.map(\.text), ["Hej.", "eh ja", "Ja."])
        XCTAssertEqual(result.map(\.speaker), ["Talare 1", "Talare 1", "Talare 2"])
        XCTAssertEqual(result.map(\.uncertainSpeaker), [false, true, false])
        XCTAssertEqual(result[1].words.map(\.uncertainSpeaker), [true, true])
    }

    /// En replik delas aldrig mellan två talare, även om meningen fortsätter.
    func testSentenceIsNeverSplitBetweenSpeakers() {
        let pieces = [ReplyPiece(start: 0, end: 1.2, speaker: 0), ReplyPiece(start: 1.2, end: 2, speaker: 1)]
        let words = [
            [word(" Jag", 0, 0.3), word(" kan", 0.3, 0.6), word(" säga", 0.6, 0.9), word(" om", 0.9, 1.0), word(" jag", 1.0, 1.15)],
            [word(" Mm.", 1.3, 1.6)]
        ]
        let result = ReplyPlan.segments(pieces: pieces, words: words, turns: [turn(0, 1.2, 0), turn(1.2, 2, 1)])
        XCTAssertEqual(result.map(\.text), ["Jag kan säga om jag", "Mm."])
        XCTAssertEqual(result.map(\.speaker), ["Talare 1", "Talare 2"])
    }
}
