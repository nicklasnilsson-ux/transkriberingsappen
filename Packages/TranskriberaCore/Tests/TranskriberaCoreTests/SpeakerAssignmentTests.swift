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
