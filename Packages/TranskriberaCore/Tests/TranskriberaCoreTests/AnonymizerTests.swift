import XCTest
@testable import TranskriberaCore

final class AnonymizerTests: XCTestCase {
    /// Bara de inbyggda reglerna, så att testerna inte beror på systemets språkmodeller.
    let rules = AnonymizationOptions(useSystemNameRecognition: false)

    func anonymize(_ text: String, _ options: AnonymizationOptions? = nil) -> String {
        Anonymizer.anonymize(text, options: options ?? rules)
    }

    // MARK: - Uppgifter med fast format

    func testPersonalNumber() {
        XCTAssertEqual(anonymize("Mitt personnummer är 19850101-1234."), "Mitt personnummer är [PERSONNUMMER 1].")
    }

    func testSamePersonalNumberInDifferentFormatsGetsSamePlaceholder() {
        XCTAssertEqual(anonymize("811218-9876 och 8112189876"), "[PERSONNUMMER 1] och [PERSONNUMMER 1]")
    }

    func testDigitsWithoutValidChecksumAreKept() {
        XCTAssertEqual(anonymize("Ordernummer 8112189875"), "Ordernummer 8112189875")
    }

    func testPhoneNumbers() {
        XCTAssertEqual(
            anonymize("Ring mig på 070-123 45 67 eller +46 8 123 456 78. Mitt nummer är alltså 0701234567."),
            "Ring mig på [TELEFON 1] eller [TELEFON 2]. Mitt nummer är alltså [TELEFON 1]."
        )
    }

    func testEmail() {
        XCTAssertEqual(
            anonymize("Mejla anna.svensson@exempel.se eller kalle snabel-a firma punkt se."),
            "Mejla [E-POST 1] eller [E-POST 2]."
        )
    }

    func testStreetAddressWithPostalCode() {
        XCTAssertEqual(anonymize("Jag bor på Storgatan 12B, 123 45 Stockholm."), "Jag bor på [ADRESS 1].")
    }

    func testLicensePlate() {
        XCTAssertEqual(
            anonymize("Bilen har registreringsnummer ABC 123."),
            "Bilen har registreringsnummer [REGNUMMER 1]."
        )
    }

    func testBankAccounts() {
        XCTAssertEqual(
            anonymize("Betala till bankgiro 5050-1055 senast fredag."),
            "Betala till bankgiro [KONTONUMMER 1] senast fredag."
        )
        XCTAssertEqual(
            anonymize("Vårt IBAN är SE45 5000 0000 0583 9825 7466."),
            "Vårt IBAN är [KONTONUMMER 1]."
        )
    }

    func testOrdinaryNumbersAreKept() {
        let text = "Mötet började klockan 09.30 och vi pratade om 2024 års budget på 1 500 000 kronor. Under 2023-2024 ökade intäkterna med 12 procent."
        XCTAssertEqual(anonymize(text), text)
    }

    // MARK: - Namn

    func testPersonNamesAreConsistent() {
        XCTAssertEqual(
            anonymize("Igår pratade jag med Anna Svensson om budgeten. Anna tyckte att Svensson hade rätt."),
            "Igår pratade jag med [PERSON 1] om budgeten. [PERSON 1] tyckte att [PERSON 1] hade rätt."
        )
    }

    func testPlaces() {
        XCTAssertEqual(
            anonymize("Vi åkte från Göteborg till Malmö och tillbaka till Göteborg."),
            "Vi åkte från [PLATS 1] till [PLATS 2] och tillbaka till [PLATS 1]."
        )
    }

    func testOrganizations() {
        var options = rules
        options.organizations = true
        XCTAssertEqual(
            anonymize("Hon jobbar på Volvo AB och har kontakt med Försäkringskassan.", options),
            "Hon jobbar på [ORGANISATION 1] och har kontakt med [ORGANISATION 2]."
        )
    }

    func testCapitalizedWordsAtSentenceStartAreKept() {
        let text = "Sedan gick vi hem. Efter det var allt lugnt."
        XCTAssertEqual(anonymize(text), text)
    }

    func testOrganizationsAreKeptByDefault() {
        let text = "Hon jobbar på Volvo AB och har kontakt med Försäkringskassan."
        XCTAssertEqual(anonymize(text), text)
    }

    func testNameFirstInSentenceIsFoundWhenSeenElsewhere() {
        var options = rules
        options.uncertainNames = true
        XCTAssertEqual(
            anonymize("Bertil kommer imorgon. Jag har pratat med Bertil.", options),
            "[NAMN 1] kommer imorgon. Jag har pratat med [NAMN 1]."
        )
    }

    func testUncertainNamesAreKeptByDefault() {
        let text = "Vi bokför i Fortnox och lönerna ligger i Visma."
        XCTAssertEqual(anonymize(text), text)

        var options = rules
        options.uncertainNames = true
        XCTAssertEqual(anonymize(text, options), "Vi bokför i [NAMN 1] och lönerna ligger i [NAMN 2].")
    }

    func testWordsThatAlsoAppearInLowercaseAreKept() {
        var options = rules
        options.uncertainNames = true
        let text = "Prislistan Euro visar minus. Vi fakturerar i euro. I kolumnen Rabatt står ingen rabatt."
        XCTAssertEqual(anonymize(text, options), text)
    }

    func testCommonFirstNamesAreHiddenAsPersons() {
        XCTAssertEqual(
            anonymize("Jag och Rasmus jobbar här. Rasmus sköter lagret."),
            "Jag och [PERSON 1] jobbar här. [PERSON 1] sköter lagret."
        )
    }

    func testAlwaysHide() {
        var options = rules
        options.alwaysHide = TextCleaning.wordList("Joj, rasmus\nKlåd")
        XCTAssertEqual(
            anonymize("Joj sa att rasmus och klåd hade rätt. Fråga Rasmus.", options),
            "[PERSON 1] sa att [PERSON 2] och [PERSON 3] hade rätt. Fråga [PERSON 2]."
        )
    }

    func testNeverHide() {
        var options = rules
        options.neverHide = ["Anna"]
        let text = "Jag pratade med Anna om saken."
        XCTAssertEqual(anonymize(text, options), text)
    }

    func testWordList() {
        XCTAssertEqual(TextCleaning.wordList(" Euro, Rabatt;\n\nVisma "), ["Euro", "Rabatt", "Visma"])
    }

    func testSpeakerNamesAreAnonymized() {
        let segments = [
            SegmentData(start: 0, end: 2, text: "Hej, jag heter Anna.", speaker: "Anna Svensson"),
            SegmentData(start: 2, end: 4, text: "Tack Anna.", speaker: "Talare 2")
        ]
        let result = Anonymizer.anonymize(segments, options: rules)
        XCTAssertEqual(result.segments[0].text, "Hej, jag heter [PERSON 1].")
        XCTAssertEqual(result.segments[0].speaker, "[PERSON 1]")
        XCTAssertEqual(result.segments[1].text, "Tack [PERSON 1].")
        XCTAssertEqual(result.segments[1].speaker, "Talare 2")
    }

    func testSystemNameRecognition() {
        let output = anonymize("Igår träffade jag Anna Svensson i Stockholm.", AnonymizationOptions())
        XCTAssertFalse(output.contains("Anna"))
        XCTAssertFalse(output.contains("Svensson"))
        XCTAssertFalse(output.contains("Stockholm"))
    }

    // MARK: - Känsliga uppgifter

    func testSensitiveTopics() {
        XCTAssertEqual(anonymize("Han är sjukskriven för depression."), "Han är [HÄLSOUPPGIFT] för [HÄLSOUPPGIFT].")
        XCTAssertEqual(anonymize("Hon röstar på Miljöpartiet."), "Hon röstar på [POLITISK ÅSIKT].")
    }

    // MARK: - Inställningar

    func testGroupsCanBeTurnedOff() {
        var options = rules
        options.names = false
        XCTAssertEqual(anonymize("Anna ringde från 070-123 45 67.", options), "Anna ringde från [TELEFON 1].")

        options = rules
        options.sensitiveTopics = false
        XCTAssertEqual(anonymize("Han är sjukskriven.", options), "Han är sjukskriven.")

        options = rules
        options.identifiers = false
        XCTAssertEqual(anonymize("Ring 070-123 45 67.", options), "Ring 070-123 45 67.")
    }

    // MARK: - Resultat

    func testResultKeepsSegmentsAndDropsWordTimingsWhenTextChanges() {
        let words = [WordTimingData(word: " Anna", start: 0, end: 1, probability: 1)]
        let segments = [
            SegmentData(start: 0, end: 1, text: "Hej då, Anna.", words: words),
            SegmentData(start: 1, end: 2, text: "Vi ses.", words: words)
        ]
        let result = Anonymizer.anonymize(segments, options: rules)
        XCTAssertEqual(result.segments.count, 2)
        XCTAssertEqual(result.segments[0].words, [])
        XCTAssertEqual(result.segments[1].words, words)
        XCTAssertEqual(result.segments[1].start, 1)
    }

    func testEntitiesAndCount() {
        let result = Anonymizer.anonymize(
            [SegmentData(start: 0, end: 1, text: "Igår pratade jag med Anna Svensson. Anna tyckte att Svensson hade rätt.")],
            options: rules
        )
        XCTAssertEqual(result.replacementCount, 3)
        XCTAssertEqual(result.entities, [AnonymizedEntity(category: .person, placeholder: "[PERSON 1]", original: "Anna Svensson")])
    }

    func testExportUsesAnonymizedText() {
        let segments = [SegmentData(start: 0, end: 2, text: "Jag pratade med Anna Svensson på 070-123 45 67.", speaker: "Kalle")]
        let anonymized = Anonymizer.anonymize(segments, options: rules).segments
        let metadata = TranscriptMetadata(title: "Möte", createdAt: Date(timeIntervalSince1970: 0), duration: 2)
        for format in ExportFormat.allCases {
            let output = TranscriptExporter.export(anonymized, metadata: metadata, format: format)
            XCTAssertFalse(output.contains("Svensson"), "\(format)")
            XCTAssertFalse(output.contains("123 45 67"), "\(format)")
            XCTAssertFalse(output.contains("Kalle"), "\(format)")
        }
    }

    func testPlaceholderPattern() {
        for placeholder in ["[PERSON 1]", "[E-POST 12]", "[POLITISK ÅSIKT]"] {
            XCTAssertNotNil(placeholder.range(of: Anonymizer.placeholderPattern, options: .regularExpression), placeholder)
        }
    }

    func testLongSegmentsWithoutWordsAreSplit() {
        let text = (0..<12).map { "ord\($0)" }.joined(separator: " ")
        let segment = SegmentData(start: 10, end: 22, text: text)
        let cues = TranscriptExporter.subtitleCues([segment], options: ExportOptions(maxSubtitleCharacters: 20))
        XCTAssertGreaterThan(cues.count, 1)
        XCTAssertTrue(cues.allSatisfy { $0.text.count <= 20 })
        XCTAssertEqual(cues.first?.start, 10)
        XCTAssertEqual(cues.last?.end, 22)
        XCTAssertEqual(cues.map(\.text).joined(separator: " "), text)
    }
}
