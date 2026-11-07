import Observation
import SwiftUI
import XCTest
import TranskriberaCore
@testable import Transkribera

/// Skrollning under uppspelning (Nicklas 2026-11-07: segt och hoppigt att skrolla medan det spelas,
/// både med och utan "Följ uppspelning"). Listan ska bara ritas om när nästa segment börjar, och
/// "Följ uppspelning" ska inte dra tillbaka texten medan man skrollar själv.
@MainActor
final class PlaybackScrollTests: XCTestCase {
    func testFocusDoesNotNotifyWhenTheSegmentIsUnchanged() {
        let focus = PlaybackFocus()
        var notified = false
        withObservationTracking { _ = focus.activeID } onChange: { notified = true }
        // Tiden tickar men samma segment spelas: listan får inte ritas om.
        focus.update(nil)
        focus.update(nil)
        XCTAssertFalse(notified, "PlaybackFocus skriver vid varje tick: hela listan ritas då om tio gånger i sekunden")
    }

    func testFollowWaitsWhileTheUserScrolls() {
        let anchor = ScrollAnchor()
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        XCTAssertFalse(anchor.userScrolledRecently(now: start), "Utan egen skrollning följer texten med")
        anchor.noteUserScroll(at: start)
        XCTAssertTrue(anchor.userScrolledRecently(now: start.addingTimeInterval(1)))
        XCTAssertTrue(anchor.userScrolledRecently(now: start.addingTimeInterval(ScrollAnchor.followPause - 0.1)))
        XCTAssertFalse(anchor.userScrolledRecently(now: start.addingTimeInterval(ScrollAnchor.followPause + 0.1)),
                       "En stund efter att man slutat skrolla följer texten med igen")
    }

    func testReadingTextIsEqualWhenTheMarkedWordIsUnchanged() {
        let words = [
            WordTimingData(word: "Hej", start: 0, end: 0.5, probability: 1),
            WordTimingData(word: "där", start: 0.5, end: 1.0, probability: 1),
        ]
        func text(at time: Double) -> ReadingText {
            ReadingText(
                text: SegmentText.attributed(text: "Hej där", query: "", words: words, currentTime: time),
                font: .reading(14), lineSpacing: 4, width: 600
            )
        }
        // Två tick i samma ord: texten ritas inte om. Nästa ord: den ritas om.
        XCTAssertEqual(text(at: 0.1), text(at: 0.2))
        XCTAssertNotEqual(text(at: 0.2), text(at: 0.7))
    }
}
