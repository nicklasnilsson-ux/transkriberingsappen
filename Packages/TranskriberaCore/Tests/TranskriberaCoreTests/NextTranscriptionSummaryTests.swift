import XCTest
@testable import TranskriberaCore

final class NextTranscriptionSummaryTests: XCTestCase {
    private func summary(speakers: Bool = false, vocabulary: Bool = false, downloaded: Bool = true) -> NextTranscriptionSummary {
        NextTranscriptionSummary(modelName: "Pianissimo", languageName: "Svenska",
                                 identifySpeakers: speakers, hasVocabulary: vocabulary, modelDownloaded: downloaded)
    }

    func testFirstRowIsModelAndLanguage() {
        XCTAssertEqual(summary().title, "Pianissimo · Svenska")
    }

    func testSecondRowOnlyWhenSomethingMoreIsOn() {
        XCTAssertNil(summary().detail, "standard: ingen andra rad, inte ens 'Finns på datorn'")
        XCTAssertEqual(summary(speakers: true).detail, "Skiljer talare")
        XCTAssertEqual(summary(vocabulary: true).detail, "Ordlista")
        XCTAssertEqual(summary(speakers: true, vocabulary: true).detail, "Skiljer talare · Ordlista")
        XCTAssertEqual(summary(downloaded: false).detail, "Laddas ner första gången")
    }

    func testAccessibilityTextHasEverything() {
        XCTAssertEqual(summary(speakers: true).accessibilityText, "Pianissimo · Svenska, Skiljer talare")
    }
}
