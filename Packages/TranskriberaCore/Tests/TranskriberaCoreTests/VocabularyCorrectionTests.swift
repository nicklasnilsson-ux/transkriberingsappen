import XCTest
@testable import TranskriberaCore

final class VocabularyCorrectionTests: XCTestCase {
    func word(_ text: String, _ start: Double) -> WordTimingData {
        WordTimingData(word: text, start: start, end: start + 0.3, probability: 1)
    }

    /// Hörfel från Pianissimo, som inte kan få ordlistan som ledtråd.
    func testNameHeardAlmostRightIsCorrected() {
        let words = [word(" Vi", 0), word(" bokför", 0.3), word(" i", 0.6), word(" Fotnox,", 0.9), word(" ja.", 1.2)]
        let segment = SegmentData(start: 0, end: 1.5, text: "Vi bokför i Fotnox, ja.", words: words)
        let result = VocabularyCorrection.apply([segment], vocabulary: ["TG", "Fortnox", "bruttovinst"])
        XCTAssertEqual(result[0].text, "Vi bokför i Fortnox, ja.")
        XCTAssertEqual(result[0].words.map(\.word), [" Vi", " bokför", " i", " Fortnox,", " ja."])
        XCTAssertEqual(result[0].words[3].start, 0.9)
    }

    func testSegmentWithoutWordsIsCorrected() {
        let segment = SegmentData(start: 0, end: 2, text: "Det står i Fortnux. Sedan Fotnox igen")
        let result = VocabularyCorrection.apply([segment], vocabulary: ["Fortnox"])
        XCTAssertEqual(result[0].text, "Det står i Fortnox. Sedan Fortnox igen")
    }

    /// Vanliga ord får inte bli namn: "visa" ligger ett tecken från "Visma".
    func testOrdinaryWordsAreKept() {
        let segment = SegmentData(start: 0, end: 2, text: "Visa mig hur ni visar det. Kan du visa?")
        let result = VocabularyCorrection.apply([segment], vocabulary: ["Visma"])
        XCTAssertEqual(result[0].text, "Visa mig hur ni visar det. Kan du visa?")
    }

    /// Fackord med gemen rättas inte, eftersom böjningar ligger lika nära som hörfel.
    func testLowercaseTermsAndShortNamesAreNotUsed() {
        let segment = SegmentData(start: 0, end: 2, text: "Vår bruttovinster och TB ökar, sa Anna")
        let result = VocabularyCorrection.apply([segment], vocabulary: ["bruttovinst", "TG", "Anne"])
        XCTAssertEqual(result[0].text, "Vår bruttovinster och TB ökar, sa Anna")
    }

    func testAmbiguousMatchIsKept() {
        XCTAssertNil(VocabularyCorrection.match("Fortnax", names: ["Fortnox", "Fortnix"]))
        XCTAssertEqual(VocabularyCorrection.match("Fortnax", names: ["Fortnox", "Visma"]), "Fortnox")
    }

    func testCapitalizationIsFixed() {
        XCTAssertEqual(VocabularyCorrection.match("FORTNOX", names: ["Fortnox"]), "Fortnox")
        XCTAssertNil(VocabularyCorrection.match("Fortnox", names: ["Fortnox"]))
    }

    func testLongNamesAllowTwoErrors() {
        XCTAssertEqual(VocabularyCorrection.match("Skandiabanke", names: ["Skandiabanken"]), "Skandiabanken")
        XCTAssertEqual(VocabularyCorrection.match("Skandjabanke", names: ["Skandiabanken"]), "Skandiabanken")
        XCTAssertNil(VocabularyCorrection.match("Fotnaxe", names: ["Fortnox"]))
    }

    func testEditDistance() {
        XCTAssertEqual(VocabularyCorrection.editDistance(Array("fotnox"), Array("fortnox")), 1)
        XCTAssertEqual(VocabularyCorrection.editDistance(Array("kitten"), Array("sitting")), 3)
        XCTAssertEqual(VocabularyCorrection.editDistance([], Array("abc")), 3)
    }
}
