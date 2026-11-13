import XCTest
@testable import TranskriberaCore

final class ShortReplyRescueTests: XCTestCase {
    private func turn(_ start: Double, _ end: Double, _ speaker: Int) -> SpeakerTurn {
        SpeakerTurn(start: start, end: end, speaker: speaker)
    }

    private func word(_ text: String, _ start: Double, _ end: Double) -> WordTimingData {
        WordTimingData(word: text, start: start, end: end, probability: 1)
    }

    private func segment(_ words: [WordTimingData], _ speaker: String) -> SegmentData {
        SegmentData(
            start: words[0].start,
            end: words[words.count - 1].end,
            text: TextCleaning.clean(words.map(\.word).joined()),
            speaker: speaker,
            words: words
        )
    }

    /// Fråga, kort svar som saknas i texten, fråga igen.
    private var questionAnswer: (segments: [SegmentData], turns: [SpeakerTurn]) {
        let segments = [
            segment([word(" Hur", 0, 0.4), word(" ofta", 0.4, 0.8), word(" loggar", 0.8, 1.3), word(" ni", 1.3, 1.5), word(" in?", 1.5, 2)], "Talare 1"),
            segment([word(" Okej.", 3.1, 3.5)], "Talare 1")
        ]
        return (segments, [turn(0, 2.2, 0), turn(2.3, 2.9, 1), turn(3.0, 3.6, 0)])
    }

    /// Mötet 2026-11-12: Pianissimo hade 9 korta svar mot Klangs 44. Ett svar som saknas
    /// helt i texten blir en egen replik på rätt plats.
    func testMissingShortAnswerIsInsertedAsItsOwnReply() {
        let (segments, turns) = questionAnswer
        let candidates = ShortReplyRescue.candidates(segments: segments, turns: turns, duration: 4)
        XCTAssertEqual(candidates.map(\.turn), [turn(2.3, 2.9, 1)])
        XCTAssertEqual(candidates.first?.clipStart ?? 0, 2.15, accuracy: 1e-9)
        XCTAssertEqual(candidates.first?.clipEnd ?? 0, 3.05, accuracy: 1e-9)

        let result = ShortReplyRescue.insert(
            [(turn(2.3, 2.9, 1), [word(" Ja,", 2.35, 2.5), word(" varje", 2.5, 2.65), word(" dag.", 2.65, 2.85)])],
            into: segments, turns: turns
        )
        XCTAssertEqual(result.map(\.text), ["Hur ofta loggar ni in?", "Ja, varje dag.", "Okej."])
        XCTAssertEqual(result.map(\.speaker), ["Talare 1", "Talare 2", "Talare 1"])
        XCTAssertEqual(result.map(\.uncertainSpeaker), [false, false, false])
    }

    /// "Talare först" klippte meningar där någon hördes samtidigt. Här läggs svaret efter
    /// meningen, och meningen hålls ihop.
    func testAnswerDuringSomeoneElsesSentenceGoesAfterTheSentence() {
        let segments = [segment([
            word(" Jag", 0, 0.3), word(" tänkte", 0.3, 0.6), word(" att", 0.6, 0.8), word(" vi", 0.8, 1.0),
            word(" börjar.", 1.0, 1.4), word(" Sen", 1.5, 1.8), word(" resten.", 1.8, 2.2)
        ], "Talare 1")]
        let turns = [turn(0, 2.3, 0), turn(0.5, 1.0, 1)]
        XCTAssertEqual(ShortReplyRescue.candidates(segments: segments, turns: turns, duration: 3).count, 1)

        let (result, added) = ShortReplyRescue.insertCounting([(turn(0.5, 1.0, 1), [word(" Mm.", 0.6, 0.9)])], into: segments, turns: turns)
        XCTAssertEqual(added, 1, "Meningen delas i två, men bara ett svar lades in")
        XCTAssertEqual(result.map(\.text), ["Jag tänkte att vi börjar.", "Mm.", "Sen resten."])
        XCTAssertEqual(result.map(\.speaker), ["Talare 1", "Talare 2", "Talare 1"])
        XCTAssertEqual(result[1].uncertainSpeaker, true, "Två hördes samtidigt: ⚠")
        XCTAssertEqual(result[1].words.map(\.uncertainSpeaker), [true])
        // Starttiderna är fortfarande i ordning.
        XCTAssertEqual(result.map(\.start), result.map(\.start).sorted())
        // Inga ord tappas eller dubbleras.
        XCTAssertEqual(result.flatMap(\.words).count, 8)
    }

    func testAnswerWithNoSentenceEndAfterItGoesAfterTheSegment() {
        let segments = [segment([word(" och", 0, 0.3), word(" sen", 0.3, 0.6), word(" så", 0.6, 0.9)], "Talare 1")]
        let turns = [turn(0, 1, 0), turn(0.2, 0.6, 1)]
        let result = ShortReplyRescue.insert([(turn(0.2, 0.6, 1), [word(" Ja.", 0.25, 0.5)])], into: segments, turns: turns)
        XCTAssertEqual(result.map(\.text), ["och sen så", "Ja."])
    }

    func testAlreadyTranscribedWordsAreNotAddedAgain() {
        let (segments, turns) = questionAnswer
        let result = ShortReplyRescue.insert([(turn(2.3, 2.9, 1), [word(" Okej.", 2.35, 2.6)])], into: segments, turns: turns)
        XCTAssertEqual(result, segments, "Okej. står redan strax efter")
    }

    func testLongEmptyOrNonSpeechResultsAreSkipped() {
        let (segments, turns) = questionAnswer
        let long = (0..<6).map { word(" ord\($0)", 2.3 + Double($0) * 0.1, 2.35 + Double($0) * 0.1) }
        for words in [long, [], [word(" [MUSIK]", 2.4, 2.8)], [word(" Ja.", 8, 8.3)]] {
            XCTAssertEqual(ShortReplyRescue.insert([(turn(2.3, 2.9, 1), words)], into: segments, turns: turns), segments, "\(words)")
        }
    }

    func testOnlyShortTurnsWithoutTheirOwnWordsAreCandidates() {
        let (segments, turns) = questionAnswer
        // För kort, för lång, och en tur där talaren redan har ord.
        let extra = turns + [turn(2.95, 3.05, 2), turn(4, 7, 2)]
        XCTAssertEqual(ShortReplyRescue.candidates(segments: segments, turns: extra, duration: 8).map(\.turn), [turn(2.3, 2.9, 1)])
        XCTAssertEqual(ShortReplyRescue.candidates(segments: segments, turns: [turn(0, 2.2, 0), turn(3.0, 3.6, 0)], duration: 4), [])
    }

    func testKnownSpeakerKeepsTheirName() {
        let segments = [
            segment([word(" Hej.", 0, 0.5)], "Talare 1"),
            segment([word(" Hej", 1, 1.3), word(" hej.", 1.3, 1.6)], "Talare 2"),
            segment([word(" Hur", 2, 2.3), word(" mår", 2.3, 2.6), word(" du?", 2.6, 3)], "Talare 1")
        ]
        let turns = [turn(0, 0.6, 0), turn(0.9, 1.7, 1), turn(1.9, 3.1, 0), turn(3.3, 3.8, 1)]
        let result = ShortReplyRescue.insert([(turn(3.3, 3.8, 1), [word(" Ja,", 3.35, 3.5), word(" bra.", 3.5, 3.7)])], into: segments, turns: turns)
        XCTAssertEqual(result.last?.speaker, "Talare 2")
        XCTAssertEqual(result.last?.text, "Ja, bra.")
    }

    /// Mötet 2026-11-13: korta bitar utan svarsord gav påhittade ord ("Ding.", "Mint.",
    /// "Läsk.", "God arrangör."). De läggs inte in.
    func testResultsWithoutAnAnswerWordAreSkipped() {
        let (segments, turns) = questionAnswer
        for words in [[word(" Ding.", 2.4, 2.8)], [word(" God", 2.35, 2.6), word(" arrangör.", 2.6, 2.85)]] {
            XCTAssertEqual(ShortReplyRescue.insert([(turn(2.3, 2.9, 1), words)], into: segments, turns: turns), segments, "\(words)")
        }
        let accepted = ShortReplyRescue.insert([(turn(2.3, 2.9, 1), [word(" Tack", 2.35, 2.5), word(" så", 2.5, 2.6), word(" mycket.", 2.6, 2.85)])],
                                               into: segments, turns: turns)
        XCTAssertEqual(accepted.map(\.text), ["Hur ofta loggar ni in?", "Tack så mycket.", "Okej."])
    }

    /// En paus i någons egen replik är inget svar (mötet 2026-11-13: "Inget." och "Bra." mitt
    /// i en monolog).
    func testPauseInsideOwnReplyIsNotAnAnswer() {
        let segments = [
            segment([word(" Det", 0, 0.3), word(" är", 0.3, 0.6), word(" så.", 0.6, 1.0)], "Talare 1"),
            segment([word(" Sen", 2.5, 2.8), word(" vidare.", 2.8, 3.2)], "Talare 1")
        ]
        let turns = [turn(0, 1.1, 0), turn(1.4, 1.9, 0), turn(2.4, 3.3, 0)]
        XCTAssertEqual(ShortReplyRescue.insert([(turn(1.4, 1.9, 0), [word(" Ja.", 1.5, 1.8)])], into: segments, turns: turns), segments)
    }

    /// En paus mitt i en mening delar den inte: svaret läggs efter meningen.
    func testPauseWithoutPunctuationDoesNotSplitTheSentence() {
        let segments = [segment([word(" Och", 0, 0.3), word(" sen", 0.3, 0.6), word(" förutom", 1.2, 1.6), word(" det.", 1.6, 2.0)], "Talare 1")]
        let turns = [turn(0, 2.1, 0), turn(0.6, 1.1, 1)]
        let result = ShortReplyRescue.insert([(turn(0.6, 1.1, 1), [word(" Mm.", 0.7, 1.0)])], into: segments, turns: turns)
        XCTAssertEqual(result.map(\.text), ["Och sen förutom det.", "Mm."])
    }
}
