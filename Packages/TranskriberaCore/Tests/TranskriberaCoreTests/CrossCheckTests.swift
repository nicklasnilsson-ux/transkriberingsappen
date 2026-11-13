import XCTest
@testable import TranskriberaCore

/// Påhittade meningar med samma sorts fel som på mötet 2026-11-12 (riktig mötestext får aldrig
/// bli testdata).
final class CrossCheckTests: XCTestCase {
    /// Ord med en tiondels sekund vardera, i ordning från `start`.
    private func words(_ text: String, from start: Double = 0) -> [WordTimingData] {
        text.split(separator: " ").enumerated().map { index, word in
            WordTimingData(word: " " + word, start: start + Double(index) * 0.1, end: start + Double(index + 1) * 0.1, probability: 1)
        }
    }

    private func segment(_ text: String, from start: Double = 0, speaker: String? = "Talare 1") -> SegmentData {
        let w = words(text, from: start)
        return SegmentData(start: w[0].start, end: w[w.count - 1].end, text: text, speaker: speaker, words: w)
    }

    private func marks(_ segments: [SegmentData]) -> [String] {
        segments.flatMap(\.words).filter { $0.alternative != nil }.map {
            "\($0.word.trimmingCharacters(in: .whitespaces))→\($0.alternative!)/\($0.alternativeLength ?? 0)"
        }
    }

    func testDifferentWordThatChangesTheMeaningIsMarked() {
        let mine = [segment("Från nästa månad bör alla beställningar gå via portalen.")]
        let other = words("Från nästa månad behöver alla beställningar gå via portalen.")
        let (result, marked) = CrossCheck.mark(mine, against: other)
        XCTAssertEqual(marked, 1)
        XCTAssertEqual(marks(result), ["bör→behöver/1"])
        XCTAssertEqual(result[0].text, mine[0].text, "Texten ändras inte förrän man väljer")
    }

    /// Mötet: ett "inte" som den ena modellen inte hörde vände betydelsen.
    func testMissingNotIsShownTogetherWithTheNextWord() {
        let (result, _) = CrossCheck.mark([segment("Så man ska bara skriva saker.")], against: words("Så man ska inte bara skriva saker."))
        XCTAssertEqual(marks(result), ["bara→inte bara/1"])
    }

    func testExtraNotIsShownTogetherWithTheNextWord() {
        let (result, _) = CrossCheck.mark([segment("Så man ska inte bara skriva saker.")], against: words("Så man ska bara skriva saker."))
        XCTAssertEqual(marks(result), ["inte→bara/2"])
    }

    /// Regeln sedan 2026-11-13 (beslut Nicklas): bara skillnader i ord som ändrar innebörden.
    /// Ord som låter helt olika, böjningar och ord som bara den andra hörde markeras inte längre;
    /// på mötet gav de en markering var 22:a sekund och fångade nästan inga fler innebördsfel.
    func testOnlyDifferencesInMeaningWordsAreMarked() {
        let (result, marked) = CrossCheck.mark(
            [segment("Vi följer samma praxis och går igenom fakturan sen, det får vi göra.")],
            against: words("Vi följer samma access och går igenom fakturorna sen, sa hon, det måste vi göra.")
        )
        XCTAssertEqual(marks(result), ["får→måste/1"])
        XCTAssertEqual(marked, 1)
    }

    func testMeaningRuleLooksAtBothSides() {
        XCTAssertTrue(CrossCheck.changesMeaning(["bör"], ["behöver"]))
        XCTAssertTrue(CrossCheck.changesMeaning([], ["inte"]))
        XCTAssertTrue(CrossCheck.changesMeaning(["inte"], []))
        XCTAssertFalse(CrossCheck.changesMeaning(["praxis"], ["access"]))
        XCTAssertFalse(CrossCheck.changesMeaning(["inte", "praxis"], ["inte", "access"]), "Samma innebördsord på båda sidor")
    }

    func testCaseSpellingPunctuationAndFillersAreNotMarked() {
        let (result, marked) = CrossCheck.mark(
            [segment("Okej, då kör vi. Det blir bra.")],
            against: words("okej då eh kör vi det öh blir bra")
        )
        XCTAssertEqual(marked, 0)
        XCTAssertEqual(marks(result), [])
    }

    func testShortAnswersOnlyTheOtherHeardAreLeftToTheShortReplyExperiment() {
        let (result, _) = CrossCheck.mark([segment("Hur ofta loggar ni in? Varje dag.")], against: words("Hur ofta loggar ni in? Ja ja. Varje dag."))
        XCTAssertEqual(marks(result), [])
    }

    func testAlternativeTakesCapitalAndPunctuationFromTheWordsItReplaces() {
        let (result, _) = CrossCheck.mark([segment("Bör vi börja?")], against: words("behöver vi börja"))
        XCTAssertEqual(marks(result), ["Bör→Behöver/1"])
        let (end, _) = CrossCheck.mark([segment("Det går nog.")], against: words("Det går inte"))
        XCTAssertEqual(marks(end), ["nog.→inte./1"])
    }

    func testLongDifferencesAreNotMarked() {
        let (result, _) = CrossCheck.mark(
            [segment("Vi ses i morgon.")],
            against: words("Vi ses och sen pratar vi om allt det andra som hände förra veckan i morgon.")
        )
        XCTAssertEqual(marks(result), [])
    }

    func testDifferenceAcrossTwoSegmentsIsNotMarked() {
        let mine = [segment("Det är inte", from: 0), segment("bra alls.", from: 1)]
        let (result, _) = CrossCheck.mark(mine, against: words("Det är ett bord alls."))
        XCTAssertTrue(marks(result).allSatisfy { !$0.contains("/2") }, "\(marks(result))")
    }

    func testMarkingAgainReplacesOldMarks() {
        let (first, _) = CrossCheck.mark([segment("Vi bör gå.")], against: words("Vi behöver gå."))
        let (again, marked) = CrossCheck.mark(first, against: words("Vi bör gå."))
        XCTAssertEqual(marked, 0)
        XCTAssertEqual(marks(again), [])
    }

    // MARK: - Välja i menyn

    func testChoosingTheAlternativeReplacesOnlyThoseWords() {
        var original = segment("Så man ska bara skriva saker.")
        original.words[4].uncertainSpeaker = true
        let (marked, _) = CrossCheck.mark([original], against: words("Så man ska inte bara skriva saker."))
        let chosen = CrossCheck.choose(alternativeAt: 3, in: marked[0])
        XCTAssertEqual(chosen.text, "Så man ska inte bara skriva saker.")
        XCTAssertEqual(chosen.words.map { $0.word.trimmingCharacters(in: .whitespaces) }, ["Så", "man", "ska", "inte", "bara", "skriva", "saker."])
        XCTAssertTrue(chosen.words.allSatisfy { $0.alternative == nil }, "Markeringen försvinner")
        XCTAssertEqual(chosen.words[5].uncertainSpeaker, true, "⚠ på \"skriva\" finns kvar")
        // De nya orden delar på det gamla ordets tid, i ordning.
        XCTAssertEqual(chosen.words[3].start, 0.3, accuracy: 1e-9)
        XCTAssertEqual(chosen.words[4].end, 0.4, accuracy: 1e-9)
        XCTAssertEqual(chosen.words.map(\.start), chosen.words.map(\.start).sorted())
    }

    func testChoosingAMultiWordMarkReplacesAllItsWords() {
        let (marked, _) = CrossCheck.mark([segment("Så man ska inte bara skriva saker.")], against: words("Så man ska bara skriva saker."))
        let chosen = CrossCheck.choose(alternativeAt: 3, in: marked[0])
        XCTAssertEqual(chosen.text, "Så man ska bara skriva saker.")
        XCTAssertEqual(chosen.words.count, 6)
    }

    func testKeepingRemovesTheMarkAndKeepsTheText() {
        let (marked, _) = CrossCheck.mark([segment("Vi bör gå.")], against: words("Vi behöver gå."))
        let kept = CrossCheck.keep(at: 1, in: marked[0])
        XCTAssertEqual(kept.text, "Vi bör gå.")
        XCTAssertEqual(marks([kept]), [])
    }

    func testChoosingWhereThereIsNoMarkChangesNothing() {
        let plain = segment("Vi bör gå.")
        XCTAssertEqual(CrossCheck.choose(alternativeAt: 0, in: plain), plain)
        XCTAssertEqual(CrossCheck.choose(alternativeAt: 9, in: plain), plain)
    }

    /// Lyssna spelar från två ord före till två ord efter (Nicklas 2026-11-13).
    func testListeningCoversTwoWordsBeforeAndAfter() {
        let (marked, _) = CrossCheck.mark([segment("Från nästa månad bör alla beställningar gå via portalen.")],
                                          against: words("Från nästa månad behöver alla beställningar gå via portalen."))
        let range = CrossCheck.listeningRange(at: 3, in: marked[0].words)
        XCTAssertEqual(range?.lowerBound ?? -1, 0.1, accuracy: 1e-9)
        XCTAssertEqual(range?.upperBound ?? -1, 0.6, accuracy: 1e-9)
        let start = CrossCheck.listeningRange(at: 0, in: words("Bör vi gå nu"))
        XCTAssertEqual(start?.lowerBound ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(start?.upperBound ?? -1, 0.3, accuracy: 1e-9)
    }

    func testLinkRoundTrip() throws {
        let link = try XCTUnwrap(CrossCheck.link(segment: 12, word: 3))
        XCTAssertEqual(CrossCheck.parse(link)?.segment, 12)
        XCTAssertEqual(CrossCheck.parse(link)?.word, 3)
        XCTAssertNil(CrossCheck.parse(URL(string: "https://example.com/12/3")!))
    }

    // MARK: - Lista för Testlabbet

    func testMarksListHasTimeSpeakerContextAndBothReadings() {
        let mine = [segment("Hej.", from: 0, speaker: "Talare 1"),
                    segment("Från nästa månad bör alla beställningar gå via portalen.", from: 60, speaker: "Talare 2")]
        let (result, _) = CrossCheck.mark(mine, against: words("Hej. Från nästa månad behöver alla beställningar gå via portalen."))
        let list = CrossCheck.marks(in: result, context: 2)
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list.first?.time ?? 0, 60.3, accuracy: 0.001)
        XCTAssertEqual(list.first?.speaker, "Talare 2")
        XCTAssertEqual(list.first?.heard, "bör")
        XCTAssertEqual(list.first?.other, "behöver")
        XCTAssertEqual(list.first?.before, "nästa månad")
        XCTAssertEqual(list.first?.after, "alla beställningar")
        let text = CrossCheck.report(list, other: "KB Large", minutes: 30)
        XCTAssertTrue(text.hasPrefix("Ord att lyssna på, markerade med KB Large: 1 ställe (2 per timme)."), text)
        XCTAssertTrue(text.contains("01:00  Talare 2  …nästa månad [bör] alla beställningar…  →  KB Large: behöver"), text)
    }

    func testMultiWordMarkListsAllItsWordsAndReportIsAnonymized() {
        let (result, _) = CrossCheck.mark([segment("Så man ska inte bara skriva saker.")], against: words("Så man ska bara skriva saker."))
        let list = CrossCheck.marks(in: result)
        XCTAssertEqual(list.map(\.heard), ["inte bara"])
        XCTAssertEqual(list.map(\.other), ["bara"])
        let text = CrossCheck.report(list, other: "KB Large", minutes: 1, anonymize: { $0.replacingOccurrences(of: "skriva", with: "[X]") })
        XCTAssertTrue(text.contains("[X]"))
        XCTAssertFalse(text.contains("skriva"))
    }

    // MARK: - Lagring

    func testMarksAreCountedWithoutDecodingAndOldWordsStillDecode() throws {
        let (marked, _) = CrossCheck.mark([segment("Vi bör gå och får se.")], against: words("Vi behöver gå och kan se."))
        let data = try JSONEncoder().encode(marked[0].words)
        XCTAssertEqual(WordTimingData.alternativeCount(inEncoded: data), 2)
        XCTAssertEqual(WordTimingData.alternativeCount(inEncoded: try JSONEncoder().encode(words("Vi bör gå."))), 0)
        // Ord sparade före experimentet saknar fälten.
        let old = Data(#"[{"word":" Hej","start":0,"end":0.5,"probability":1}]"#.utf8)
        let decoded = try JSONDecoder().decode([WordTimingData].self, from: old)
        XCTAssertNil(decoded[0].alternative)
    }

    func testChangesFindsReplacementsInsertionsAndRemovals() {
        XCTAssertEqual(CrossCheck.changes(old: ["a", "b", "c"], new: ["a", "x", "c"]), [.init(old: 1..<2, new: 1..<2)])
        XCTAssertEqual(CrossCheck.changes(old: ["a", "c"], new: ["a", "b", "c"]), [.init(old: 1..<1, new: 1..<2)])
        XCTAssertEqual(CrossCheck.changes(old: ["a", "b", "c"], new: ["a", "c"]), [.init(old: 1..<2, new: 1..<1)])
        XCTAssertEqual(CrossCheck.changes(old: [], new: []), [])
    }
}
