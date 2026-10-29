import XCTest
@testable import TranskriberaCore

final class TokenWordsTests: XCTestCase {
    func testPiecesAreJoinedIntoWords() {
        let tokens = [
            TimedToken(text: "▁Hel", start: 0.0, end: 0.16),
            TimedToken(text: "t", start: 0.16, end: 0.24),
            TimedToken(text: " enkel", start: 0.32, end: 0.56),
            TimedToken(text: "t", start: 0.56, end: 0.64)
        ]
        let words = TokenWords.words(from: tokens)
        XCTAssertEqual(words.map(\.word), [" Helt", " enkelt"])
        XCTAssertEqual(words[1].start, 0.32)
        XCTAssertEqual(words[1].end, 0.64)
    }

    /// Felet från intervjun: punkten efter sista ordet räckte fram till nästa talares
    /// första ord, så "enkelt." fick ett slut flera sekunder för sent.
    func testPunctuationDoesNotStretchTheWordIntoTheNextTurn() {
        let tokens = [
            TimedToken(text: " enkel", start: 2.0, end: 2.24),
            TimedToken(text: "t", start: 2.24, end: 2.32),
            TimedToken(text: ".", start: 2.32, end: 4.8),
            TimedToken(text: " Ja", start: 4.8, end: 5.0)
        ]
        let words = TokenWords.words(from: tokens)
        XCTAssertEqual(words.map(\.word), [" enkelt.", " Ja"])
        XCTAssertEqual(words[0].end, 2.32)
    }

    func testLongTokenIsCapped() {
        let words = TokenWords.words(from: [TimedToken(text: " Mm", start: 1.0, end: 6.0)])
        XCTAssertEqual(words[0].end, 1.0 + TokenWords.maxTokenDuration)
    }

    func testBlankTokensAreSkipped() {
        let tokens = [TimedToken(text: "<blank>", start: 0, end: 0.1), TimedToken(text: " Hej", start: 0.1, end: 0.3)]
        XCTAssertEqual(TokenWords.words(from: tokens).map(\.word), [" Hej"])
    }
}
