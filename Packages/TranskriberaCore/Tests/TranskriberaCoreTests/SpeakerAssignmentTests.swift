import XCTest
@testable import TranskriberaCore

final class SpeakerAssignmentTests: XCTestCase {
    func word(_ text: String, _ start: Double, _ end: Double) -> WordTimingData {
        WordTimingData(word: text, start: start, end: end, probability: 1)
    }

    func testSegmentIsSplitWhereTheSpeakerChangesWithoutPause() {
        let words = [
            word(" Hur", 0.0, 0.3), word(" ofta", 0.3, 0.6), word(" är", 0.6, 0.8), word(" ni", 0.8, 1.0),
            word(" inne?", 1.0, 1.5), word(" Varje", 1.5, 1.9), word(" dag.", 1.9, 2.3)
        ]
        let segment = SegmentData(start: 0, end: 2.3, text: "Hur ofta är ni inne? Varje dag.", words: words)
        let turns = [SpeakerTurn(start: 0, end: 1.5, speaker: 4), SpeakerTurn(start: 1.5, end: 2.4, speaker: 1)]

        let result = SpeakerAssignment.assign([segment], turns: turns)
        XCTAssertEqual(result.map(\.text), ["Hur ofta är ni inne?", "Varje dag."])
        XCTAssertEqual(result.map(\.speaker), ["Talare 1", "Talare 2"])
        XCTAssertEqual(result[1].start, 1.5)
        XCTAssertEqual(result[1].end, 2.3)
        XCTAssertEqual(result[1].words.count, 2)
    }

    func testWholeSegmentKeepsItsTextAndTimes() {
        let words = [word(" Ja", 0.2, 0.4), word(" visst.", 0.4, 0.9)]
        let segment = SegmentData(start: 0, end: 1, text: "Ja visst.", words: words)
        let result = SpeakerAssignment.assign([segment], turns: [SpeakerTurn(start: 0, end: 1, speaker: 0)])
        XCTAssertEqual(result, [SegmentData(start: 0, end: 1, text: "Ja visst.", speaker: "Talare 1", words: words)])
    }

    func testSingleWordInsideAnotherSpeakersSentenceIsSmoothed() {
        let words = [word(" Vi", 0, 0.3), word(" har", 0.3, 0.6), word(" många", 0.6, 0.9), word(" kunder.", 0.9, 1.4)]
        let segment = SegmentData(start: 0, end: 1.4, text: "Vi har många kunder.", words: words)
        let turns = [
            SpeakerTurn(start: 0, end: 0.58, speaker: 0),
            SpeakerTurn(start: 0.58, end: 0.92, speaker: 1),
            SpeakerTurn(start: 0.92, end: 1.5, speaker: 0)
        ]
        let result = SpeakerAssignment.assign([segment], turns: turns)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].speaker, "Talare 1")
    }

    /// Fel från en riktig intervju (Pianissimo): ordtiderna låg lite efter talarturerna, så
    /// sista ordet i repliken hamnade hos nästa talare: "…felaktiga siffror helt / enkelt."
    func testLastWordOfATurnStaysWithItsSpeaker() {
        let words = [
            word(" felaktiga", 0.0, 0.5), word(" siffror", 0.5, 0.9), word(" helt", 0.9, 1.1),
            word(" enkelt.", 1.1, 1.6)
        ]
        let segment = SegmentData(start: 0, end: 1.6, text: "felaktiga siffror helt enkelt.", words: words)
        let turns = [SpeakerTurn(start: 0, end: 1.2, speaker: 0), SpeakerTurn(start: 1.2, end: 3, speaker: 1)]
        let result = SpeakerAssignment.assign([segment], turns: turns)
        XCTAssertEqual(result.map(\.text), ["felaktiga siffror helt enkelt."])
        XCTAssertEqual(result.map(\.speaker), ["Talare 1"])
    }

    /// "Överkurs / för mig." – två ord hos fel talare i slutet av en mening.
    func testTwoTrailingWordsWithoutPauseJoinTheSentence() {
        let words = [
            word(" Det", 0.0, 0.2), word(" är", 0.2, 0.4), word(" överkurs", 0.4, 1.0),
            word(" för", 1.0, 1.2), word(" mig.", 1.2, 1.5)
        ]
        let segment = SegmentData(start: 0, end: 1.5, text: "Det är överkurs för mig.", words: words)
        let turns = [SpeakerTurn(start: 0, end: 1.0, speaker: 0), SpeakerTurn(start: 1.0, end: 2, speaker: 1)]
        let result = SpeakerAssignment.assign([segment], turns: turns)
        XCTAssertEqual(result.map(\.speaker), ["Talare 1"])
    }

    /// Början av en mening hos fel talare: "Jag skulle / lita på assistenten, absolut."
    func testTwoLeadingWordsWithoutPauseJoinTheSentence() {
        let words = [
            word(" Jag", 0.0, 0.2), word(" skulle", 0.2, 0.5), word(" lita", 0.5, 0.8),
            word(" på", 0.8, 0.9), word(" assistenten,", 0.9, 1.6), word(" absolut.", 1.6, 2.1)
        ]
        let question = SegmentData(start: -1, end: -0.5, text: "Okej?", words: [word(" Okej?", -1, -0.5)])
        let segment = SegmentData(start: 0, end: 2.1, text: "Jag skulle lita på assistenten, absolut.", words: words)
        let turns = [SpeakerTurn(start: -1, end: 0.5, speaker: 0), SpeakerTurn(start: 0.5, end: 3, speaker: 1)]
        let result = SpeakerAssignment.assign([question, segment], turns: turns)
        XCTAssertEqual(result.map(\.text), ["Okej?", "Jag skulle lita på assistenten, absolut."])
        XCTAssertEqual(result.map(\.speaker), ["Talare 1", "Talare 2"])
    }

    func testShortReplyAfterAPauseIsKept() {
        let words = [
            word(" Kommer", 0.0, 0.4), word(" du", 0.4, 0.6), word(" ihåg", 0.6, 1.0),
            word(" ja", 1.5, 1.7)
        ]
        let segment = SegmentData(start: 0, end: 1.7, text: "Kommer du ihåg ja", words: words)
        let turns = [SpeakerTurn(start: 0, end: 1.2, speaker: 0), SpeakerTurn(start: 1.2, end: 2, speaker: 1)]
        let result = SpeakerAssignment.assign([segment], turns: turns)
        XCTAssertEqual(result.map(\.text), ["Kommer du ihåg", "ja"])
        XCTAssertEqual(result.map(\.speaker), ["Talare 1", "Talare 2"])
    }

    func testLongerRunInsideASentenceStillSplits() {
        let words = [
            word(" Vi", 0.0, 0.2), word(" har", 0.2, 0.4), word(" det", 0.4, 0.6),
            word(" ja", 0.6, 0.8), word(" det", 0.8, 1.0), word(" stämmer", 1.0, 1.4)
        ]
        let segment = SegmentData(start: 0, end: 1.4, text: "Vi har det ja det stämmer", words: words)
        let turns = [SpeakerTurn(start: 0, end: 0.6, speaker: 0), SpeakerTurn(start: 0.6, end: 2, speaker: 1)]
        let result = SpeakerAssignment.assign([segment], turns: turns)
        XCTAssertEqual(result.map(\.text), ["Vi har det", "ja det stämmer"])
    }

    /// Fel i 0.5.1: meningen fortsatte i nästa segment och de två sista orden hamnade hos
    /// nästa talare: "Det står Claude / hos dig."
    func testShortRunInNextSegmentJoinsTheSentence() {
        let first = SegmentData(start: 0, end: 1.0, text: "Det står Claude", words: [
            word(" Det", 0.0, 0.2), word(" står", 0.2, 0.5), word(" Claude", 0.5, 1.0)
        ])
        let second = SegmentData(start: 1.05, end: 1.6, text: "hos dig.", words: [
            word(" hos", 1.05, 1.3), word(" dig.", 1.3, 1.6)
        ])
        let turns = [SpeakerTurn(start: 0, end: 1.02, speaker: 0), SpeakerTurn(start: 1.02, end: 3, speaker: 1)]
        let result = SpeakerAssignment.assign([first, second], turns: turns)
        XCTAssertEqual(result.map(\.text), ["Det står Claude", "hos dig."])
        XCTAssertEqual(result.map(\.speaker), ["Talare 1", "Talare 1"])
    }

    /// Ett kort svar i ett eget segment efter en fråga ska behålla sin talare.
    func testShortReplyInOwnSegmentAfterQuestionIsKept() {
        let first = SegmentData(start: 0, end: 1.0, text: "Hur ofta?", words: [
            word(" Hur", 0.0, 0.4), word(" ofta?", 0.4, 1.0)
        ])
        let second = SegmentData(start: 1.05, end: 1.6, text: "Varje dag.", words: [
            word(" Varje", 1.05, 1.3), word(" dag.", 1.3, 1.6)
        ])
        let third = SegmentData(start: 1.65, end: 2.5, text: "Okej, och sedan", words: [
            word(" Okej,", 1.65, 1.9), word(" och", 1.9, 2.1), word(" sedan", 2.1, 2.5)
        ])
        let turns = [
            SpeakerTurn(start: 0, end: 1.02, speaker: 0),
            SpeakerTurn(start: 1.02, end: 1.62, speaker: 1),
            SpeakerTurn(start: 1.62, end: 3, speaker: 0)
        ]
        let result = SpeakerAssignment.assign([first, second, third], turns: turns)
        XCTAssertEqual(result.map(\.speaker), ["Talare 1", "Talare 2", "Talare 1"])
    }

    func testWordsWithoutOverlapGetPreviousSpeaker() {
        let first = SegmentData(start: 0, end: 1, text: "Hej.", words: [word(" Hej.", 0, 1)])
        let second = SegmentData(start: 5, end: 6, text: "Mm.", words: [word(" Mm.", 5, 6)])
        let result = SpeakerAssignment.assign([first, second], turns: [SpeakerTurn(start: 0, end: 1, speaker: 2)])
        XCTAssertEqual(result.map(\.speaker), ["Talare 1", "Talare 1"])
    }

    func testSegmentsWithoutWordsUseOverlap() {
        let segments = [
            SegmentData(start: 0, end: 2, text: "Första."),
            SegmentData(start: 2, end: 4, text: "Andra.")
        ]
        let turns = [SpeakerTurn(start: 0, end: 2.2, speaker: 1), SpeakerTurn(start: 2.2, end: 4, speaker: 0)]
        let result = SpeakerAssignment.assign(segments, turns: turns)
        XCTAssertEqual(result.map(\.speaker), ["Talare 1", "Talare 2"])
    }

    func testNoTurnsLeavesSegmentsUnchanged() {
        let segments = [SegmentData(start: 0, end: 1, text: "Hej.")]
        XCTAssertEqual(SpeakerAssignment.assign(segments, turns: []), segments)
    }
}
