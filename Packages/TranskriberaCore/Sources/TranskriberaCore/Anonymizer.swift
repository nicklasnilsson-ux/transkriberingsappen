import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

/// Typ av uppgift som maskeras vid anonymisering.
public enum AnonymizationCategory: String, CaseIterable, Codable, Sendable {
    case person
    case place
    case organization
    /// Egennamn som inte gick att typbestämma.
    case name
    case personalNumber
    case phone
    case email
    case address
    case bankAccount
    case cardNumber
    case licensePlate
    case health
    case religion
    case politics
    case sexuality
    case tradeUnion

    /// Texten i platshållaren, t.ex. "PERSON" i "[PERSON 1]".
    public var label: String {
        switch self {
        case .person: return "PERSON"
        case .place: return "PLATS"
        case .organization: return "ORGANISATION"
        case .name: return "NAMN"
        case .personalNumber: return "PERSONNUMMER"
        case .phone: return "TELEFON"
        case .email: return "E-POST"
        case .address: return "ADRESS"
        case .bankAccount: return "KONTONUMMER"
        case .cardNumber: return "KORTNUMMER"
        case .licensePlate: return "REGNUMMER"
        case .health: return "HÄLSOUPPGIFT"
        case .religion: return "RELIGION"
        case .politics: return "POLITISK ÅSIKT"
        case .sexuality: return "SEXUELL LÄGGNING"
        case .tradeUnion: return "FACKTILLHÖRIGHET"
        }
    }

    public var group: AnonymizationGroup {
        switch self {
        case .person, .place, .organization, .name:
            return .names
        case .personalNumber, .phone, .email, .address, .bankAccount, .cardNumber, .licensePlate:
            return .identifiers
        case .health, .religion, .politics, .sexuality, .tradeUnion:
            return .sensitiveTopics
        }
    }

    /// Namn och nummer numreras så att samma uppgift alltid får samma platshållare.
    var isNumbered: Bool { group != .sensitiveTopics }
}

/// Grupper som kan slås av och på var för sig i inställningarna.
public enum AnonymizationGroup: String, CaseIterable, Sendable {
    /// Personer, platser och organisationer.
    case names
    /// Personnummer, telefon, e-post, adresser, kontonummer, regnummer.
    case identifiers
    /// Känsliga personuppgifter enligt GDPR (hälsa, religion, politik m.m.). Fångas bara delvis.
    case sensitiveTopics
}

public struct AnonymizationOptions: Hashable, Sendable {
    public var names: Bool
    public var identifiers: Bool
    public var sensitiveTopics: Bool
    /// Använd Apples språkanalys (NaturalLanguage) som komplement till de inbyggda reglerna.
    public var useSystemNameRecognition: Bool

    public init(names: Bool = true, identifiers: Bool = true, sensitiveTopics: Bool = true, useSystemNameRecognition: Bool = true) {
        self.names = names
        self.identifiers = identifiers
        self.sensitiveTopics = sensitiveTopics
        self.useSystemNameRecognition = useSystemNameRecognition
    }

    public func includes(_ group: AnonymizationGroup) -> Bool {
        switch group {
        case .names: return names
        case .identifiers: return identifiers
        case .sensitiveTopics: return sensitiveTopics
        }
    }
}

/// En uppgift som har maskerats.
public struct AnonymizedEntity: Hashable, Sendable {
    public var category: AnonymizationCategory
    public var placeholder: String
    public var original: String
}

public struct AnonymizationResult: Sendable {
    /// Samma segment i samma ordning, med maskerad text och talare. Ordtidsstämplar
    /// tas bort i segment vars text ändrats, eftersom de innehåller originalorden.
    public var segments: [SegmentData]
    /// Unika maskerade uppgifter i den ordning de först förekommer.
    public var entities: [AnonymizedEntity]
    /// Totalt antal ersättningar i text och talarnamn.
    public var replacementCount: Int
}

/// Maskerar personuppgifter i transkriberingar, helt lokalt.
///
/// Uppgifter med fast format (personnummer, telefon, e-post m.m.) hittas med reguljära
/// uttryck och kontroller. Namn hittas med regler för versaler i löpande text, ordlistor
/// och (på macOS) Apples NaturalLanguage. Samma namn eller nummer får samma platshållare
/// i hela transkriberingen, t.ex. "[PERSON 1]". Ingen automatisk anonymisering är
/// fullständig: texten bör granskas innan den delas.
public enum Anonymizer {
    /// Matchar platshållare som Anonymizer skriver, t.ex. "[PERSON 1]" eller "[HÄLSOUPPGIFT]".
    public static let placeholderPattern = #"\[[A-ZÅÄÖ\- ]+(?: \d+)?\]"#

    public static func anonymize(_ segments: [SegmentData], options: AnonymizationOptions = AnonymizationOptions()) -> AnonymizationResult {
        let registry = PlaceholderRegistry()
        let names = NameDetector(texts: segments.map(\.text), speakers: segments.compactMap(\.speaker), options: options)
        var count = 0

        let result = segments.map { segment -> SegmentData in
            var output = segment
            var spans: [Span] = []
            if options.identifiers { spans += identifierSpans(in: segment.text) }
            if options.sensitiveTopics { spans += sensitiveSpans(in: segment.text) }
            if options.names { spans += names.spans(in: segment.text) }
            let (text, replaced) = apply(spans, to: segment.text, registry: registry)
            count += replaced

            if options.names, let speaker = segment.speaker, let span = names.speakerSpan(for: speaker) {
                output.speaker = registry.placeholder(for: span, original: speaker)
                count += 1
            }
            if text != segment.text {
                output.text = text
                output.words = []
            }
            return output
        }
        return AnonymizationResult(segments: result, entities: registry.entities, replacementCount: count)
    }

    /// Maskerar en enskild text.
    public static func anonymize(_ text: String, options: AnonymizationOptions = AnonymizationOptions()) -> String {
        anonymize([SegmentData(start: 0, end: 0, text: text)], options: options).segments[0].text
    }

    // MARK: - Ersättning

    struct Span {
        var range: Range<String.Index>
        var category: AnonymizationCategory
        /// Normaliserad nyckel så att olika skrivsätt av samma uppgift får samma platshållare.
        var key: String
        /// Andra nycklar som ska ge samma platshållare (t.ex. förnamn och efternamn var för sig).
        var aliases: [String] = []
    }

    /// Ersätter spannen i prioritetsordning; spann som överlappar ett tidigare spann hoppas över.
    static func apply(_ spans: [Span], to text: String, registry: PlaceholderRegistry) -> (String, Int) {
        var accepted: [Span] = []
        for span in spans where !accepted.contains(where: { $0.range.overlaps(span.range) }) {
            accepted.append(span)
        }
        guard !accepted.isEmpty else { return (text, 0) }
        accepted.sort { $0.range.lowerBound < $1.range.lowerBound }

        var result = ""
        var cursor = text.startIndex
        for span in accepted {
            result += text[cursor..<span.range.lowerBound]
            result += registry.placeholder(for: span, original: String(text[span.range]))
            cursor = span.range.upperBound
        }
        result += text[cursor...]
        return (result, accepted.count)
    }

    final class PlaceholderRegistry {
        private var placeholders: [String: String] = [:]
        private var counters: [AnonymizationCategory: Int] = [:]
        private var seenUnnumbered = Set<String>()
        private(set) var entities: [AnonymizedEntity] = []

        func placeholder(for span: Span, original: String) -> String {
            let category = span.category
            guard category.isNumbered else {
                let placeholder = "[\(category.label)]"
                if seenUnnumbered.insert("\(category.rawValue)|\(span.key)").inserted {
                    entities.append(AnonymizedEntity(category: category, placeholder: placeholder, original: original))
                }
                return placeholder
            }
            let id = Self.id(category, span.key)
            if let existing = placeholders[id] { return existing }

            let placeholder: String
            if let aliased = span.aliases.lazy.compactMap({ self.placeholders[Self.id(category, $0)] }).first {
                placeholder = aliased
            } else {
                let number = counters[category, default: 0] + 1
                counters[category] = number
                placeholder = "[\(category.label) \(number)]"
                entities.append(AnonymizedEntity(category: category, placeholder: placeholder, original: original))
            }
            placeholders[id] = placeholder
            for alias in span.aliases where placeholders[Self.id(category, alias)] == nil {
                placeholders[Self.id(category, alias)] = placeholder
            }
            return placeholder
        }

        private static func id(_ category: AnonymizationCategory, _ key: String) -> String {
            "\(category.rawValue)|\(key)"
        }
    }

    // MARK: - Uppgifter med fast format

    static func identifierSpans(in text: String) -> [Span] {
        var spans: [Span] = []

        for match in Patterns.email.matches(in: text) {
            let key = String(text[match]).lowercased().filter { !$0.isWhitespace }
            spans.append(Span(range: match, category: .email, key: key))
        }
        for match in Patterns.iban.matches(in: text) {
            spans.append(Span(range: match, category: .bankAccount, key: digitsAndLetters(text[match])))
        }
        for match in Patterns.personalNumber.matches(in: text) where isPersonalNumber(text[match]) {
            spans.append(Span(range: match, category: .personalNumber, key: personalNumberKey(text[match])))
        }
        for match in Patterns.cardNumber.matches(in: text) {
            let digits = onlyDigits(text[match])
            guard (13...19).contains(digits.count), luhn(digits) else { continue }
            spans.append(Span(range: match, category: .cardNumber, key: digits))
        }
        for match in Patterns.accountWithContext.matches(in: text, group: 1) {
            let digits = onlyDigits(text[match])
            let after = text[match.upperBound...].prefix(10).lowercased()
            let isAmount = ["kr", "kronor", "sek", "procent", "%", ":-"].contains { after.hasPrefix(" \($0)") || after.hasPrefix($0) }
            guard digits.count >= 6, !isAmount else { continue }
            spans.append(Span(range: match, category: .bankAccount, key: digits))
        }
        for pattern in [Patterns.swedishPhone, Patterns.internationalPhone] {
            for match in pattern.matches(in: text) {
                let key = phoneKey(text[match])
                guard (8...15).contains(key.count) else { continue }
                spans.append(Span(range: match, category: .phone, key: key))
            }
        }
        for match in Patterns.licensePlate.matches(in: text) {
            spans.append(Span(range: match, category: .licensePlate, key: digitsAndLetters(text[match])))
        }
        for pattern in [Patterns.streetAddress, Patterns.postalCode] {
            for match in pattern.matches(in: text) {
                let key = text[match].lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
                spans.append(Span(range: match, category: .address, key: key))
            }
        }
        return spans
    }

    /// Kontrollerar datumdelen och, när siffrorna står ihop utan skiljetecken, kontrollsiffran.
    static func isPersonalNumber(_ match: Substring) -> Bool {
        let digits = onlyDigits(match)
        guard digits.count == 10 || digits.count == 12 else { return false }
        let short = String(digits.suffix(10))
        let chars = Array(short)
        guard let month = Int(String(chars[2...3])), let day = Int(String(chars[4...5])) else { return false }
        // Samordningsnummer har dag + 60.
        guard (1...12).contains(month), (1...31).contains(day) || (61...91).contains(day) else { return false }

        let hasSeparator = match.contains { !$0.isNumber }
        let onlyWhitespaceSeparator = hasSeparator && !match.contains { "-+–".contains($0) }
        if digits.count == 10 {
            // Tio siffror som börjar på 0 är oftast ett telefonnummer.
            if digits.hasPrefix("0") && (!hasSeparator || onlyWhitespaceSeparator) { return false }
            if !hasSeparator { return luhn(short) }
        }
        return true
    }

    static func personalNumberKey(_ match: Substring) -> String {
        String(onlyDigits(match).suffix(10))
    }

    /// Samma nummer i olika format (+46 70…, 070…) får samma nyckel.
    static func phoneKey(_ match: Substring) -> String {
        let trimmed = match.trimmingCharacters(in: .whitespaces)
        var digits = onlyDigits(match)
        if trimmed.hasPrefix("+46") {
            digits = "0" + digits.dropFirst(2)
        } else if digits.hasPrefix("0046") {
            digits = "0" + digits.dropFirst(4)
        }
        if digits.hasPrefix("00") { digits = String(digits.dropFirst()) }
        return digits
    }

    static func luhn(_ digits: String) -> Bool {
        let values = digits.compactMap(\.wholeNumberValue)
        guard values.count == digits.count, !values.isEmpty else { return false }
        var sum = 0
        for (offset, value) in values.reversed().enumerated() {
            if offset % 2 == 1 {
                let doubled = value * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += value
            }
        }
        return sum % 10 == 0
    }

    static func onlyDigits<S: StringProtocol>(_ text: S) -> String {
        String(text.filter(\.isASCIIDigit))
    }

    static func digitsAndLetters<S: StringProtocol>(_ text: S) -> String {
        String(text.filter { $0.isLetter || $0.isNumber }).uppercased()
    }

    // MARK: - Känsliga personuppgifter

    static func sensitiveSpans(in text: String) -> [Span] {
        var spans: [Span] = []
        for (category, pattern) in Patterns.sensitive {
            for match in pattern.matches(in: text) {
                spans.append(Span(range: match, category: category, key: text[match].lowercased()))
            }
        }
        return spans
    }
}

// MARK: - Namn

/// Hittar egennamn. Regler: ett ord med stor bokstav mitt i en mening är nästan alltid
/// ett egennamn på svenska. Ord först i en mening räknas bara om de förekommer som namn
/// någon annanstans, finns i ordlistorna eller känns igen av NaturalLanguage.
struct NameDetector {
    struct Token {
        var range: Range<String.Index>
        var key: String
        var isSentenceInitial: Bool
    }

    struct Group {
        var range: Range<String.Index>
        var parts: [String]
    }

    /// Ord som förekommer med stor bokstav mitt i en mening någonstans i texten.
    private var knownNames = Set<String>()
    /// Kategori från NaturalLanguage, per namn och per ord.
    private var hints: [String: AnonymizationCategory] = [:]
    /// Bestämd kategori per namn eller namnord, så att t.ex. ett efternamn som
    /// förekommer ensamt behandlas som samma person som det fullständiga namnet.
    private var decided: [String: AnonymizationCategory] = [:]

    init(texts: [String], speakers: [String], options: AnonymizationOptions) {
        guard options.names else { return }

        for text in texts {
            for token in Self.tokens(in: text) where !token.isSentenceInitial && Self.isCandidate(token, in: text) {
                knownNames.insert(token.key)
            }
        }
        for speaker in Set(speakers) where !Self.isGenericSpeaker(speaker) {
            let parts = Self.speakerParts(speaker)
            knownNames.formUnion(parts)
            decided[Self.key(for: parts)] = .person
            for part in parts { decided[part] = .person }
        }
        if options.useSystemNameRecognition {
            hints = Self.systemHints(for: texts.joined(separator: "\n"))
        }
        // Delarna i fullständiga personnamn räknas som personer även när de står ensamma.
        for text in texts {
            for group in groups(in: text) where group.parts.count > 1 && category(for: group.parts) == .person {
                for part in group.parts where decided[part] == nil {
                    decided[part] = .person
                }
            }
        }
    }

    static func key(for parts: [String]) -> String { parts.joined(separator: " ") }

    static func speakerParts(_ speaker: String) -> [String] {
        speaker.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
    }

    func speakerSpan(for speaker: String) -> Anonymizer.Span? {
        guard !Self.isGenericSpeaker(speaker) else { return nil }
        let parts = Self.speakerParts(speaker)
        guard !parts.isEmpty else { return nil }
        return Anonymizer.Span(
            range: speaker.startIndex..<speaker.endIndex,
            category: .person,
            key: Self.key(for: parts),
            aliases: parts.count > 1 ? parts : []
        )
    }

    /// "Talare 1", "Speaker 2" m.fl. är inga personuppgifter.
    static func isGenericSpeaker(_ speaker: String) -> Bool {
        speaker.range(of: #"^\s*(?:talare|speaker|spk|person)[ _-]?\d+\s*$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    func spans(in text: String) -> [Anonymizer.Span] {
        groups(in: text).map { group in
            var range = group.range
            var kind = category(for: group.parts)
            if let follower = Lexicon.organizationFollower.firstMatch(in: text, range: range.upperBound..<text.endIndex) {
                range = range.lowerBound..<follower.upperBound
                kind = .organization
            }
            return Anonymizer.Span(
                range: range,
                category: kind,
                key: Self.key(for: group.parts),
                aliases: kind == .person && group.parts.count > 1 ? group.parts : []
            )
        }
    }

    /// Namnord som står intill varandra slås ihop, t.ex. "Anna Svensson".
    private func groups(in text: String) -> [Group] {
        let tokens = Self.tokens(in: text).filter { isName($0, in: text) }
        var groups: [Group] = []
        var index = 0
        while index < tokens.count {
            var members = [tokens[index]]
            while index + 1 < tokens.count, Self.joins(members[members.count - 1], tokens[index + 1], in: text) {
                index += 1
                members.append(tokens[index])
            }
            index += 1
            groups.append(Group(
                range: members[0].range.lowerBound..<members[members.count - 1].range.upperBound,
                parts: members.map(\.key)
            ))
        }
        return groups
    }

    private func isName(_ token: Token, in text: String) -> Bool {
        guard Self.isCandidate(token, in: text) else {
            // Förkortningar räknas bara om de är kända platser (USA m.fl.).
            return Lexicon.contains(Lexicon.places, token.key) && !Lexicon.stopwords.contains(token.key)
        }
        if !token.isSentenceInitial { return true }
        return Lexicon.contains(knownNames, token.key)
            || decided[token.key] != nil
            || hints[token.key] != nil
            || Lexicon.contains(Lexicon.firstNames, token.key)
            || Lexicon.contains(Lexicon.places, token.key)
    }

    private func category(for parts: [String]) -> AnonymizationCategory {
        let key = Self.key(for: parts)
        if let category = decided[key] { return category }
        if parts.contains(where: { decided[$0] == .person }) { return .person }
        if let hint = hints[key] ?? parts.lazy.compactMap({ self.hints[$0] }).first { return hint }
        if Lexicon.places.contains(key) || parts.allSatisfy({ Lexicon.contains(Lexicon.places, $0) }) { return .place }
        if parts.contains(where: { Lexicon.organizationWords.contains($0) || Lexicon.hasSuffix($0, Lexicon.organizationSuffixes) }) {
            return .organization
        }
        if let last = parts.last, Lexicon.hasSuffix(last, Lexicon.streetSuffixes) { return .place }
        if Lexicon.contains(Lexicon.firstNames, parts[0]) { return .person }
        if parts.contains(where: { Lexicon.hasSuffix($0, Lexicon.surnameSuffixes) }) { return .person }
        if parts.count > 1 { return .person }
        if Lexicon.hasSuffix(parts[0], Lexicon.placeSuffixes) || Lexicon.contains(Lexicon.places, parts[0]) {
            return .place
        }
        return .name
    }

    // MARK: Ord

    static func tokens(in text: String) -> [Token] {
        Lexicon.capitalizedWord.matches(in: text).map { range in
            Token(
                range: range,
                key: text[range].lowercased(),
                isSentenceInitial: isSentenceInitial(range.lowerBound, in: text)
            )
        }
    }

    static func isCandidate(_ token: Token, in text: String) -> Bool {
        !Lexicon.stopwords.contains(token.key) && !looksLikeAcronym(text[token.range])
    }

    /// "USA", "AB", "TV-serien", "IT-avdelningen" …
    static func looksLikeAcronym(_ word: Substring) -> Bool {
        let letters = word.prefix(2)
        return letters.count == 2 && letters.allSatisfy(\.isUppercase)
    }

    static func isSentenceInitial(_ index: String.Index, in text: String) -> Bool {
        var position = index
        while position > text.startIndex {
            let previous = text.index(before: position)
            let character = text[previous]
            if character.isWhitespace {
                position = previous
                continue
            }
            return ".!?…:;\"”“«»(–—-".contains(character)
        }
        return true
    }

    /// Två namnord hör ihop om bara ett mellanslag (eller "von", "af" …) skiljer dem åt.
    static func joins(_ first: Token, _ second: Token, in text: String) -> Bool {
        guard first.range.upperBound <= second.range.lowerBound else { return false }
        let between = text[first.range.upperBound..<second.range.lowerBound]
        if between == " " { return true }
        let parts = between.split(separator: " ", omittingEmptySubsequences: false)
        return parts.count == 3 && parts[0].isEmpty && parts[2].isEmpty && Lexicon.nameParticles.contains(String(parts[1]))
    }

    // MARK: NaturalLanguage

    static func systemHints(for text: String) -> [String: AnonymizationCategory] {
        var hints: [String: AnonymizationCategory] = [:]
        #if canImport(NaturalLanguage)
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: options) { tag, range in
            let category: AnonymizationCategory?
            switch tag {
            case .some(.personalName): category = .person
            case .some(.placeName): category = .place
            case .some(.organizationName): category = .organization
            default: category = nil
            }
            guard let category, text[range].first?.isUppercase == true else { return true }
            let parts = tokens(in: String(text[range])).map(\.key)
            guard !parts.isEmpty, !parts.contains(where: { Lexicon.stopwords.contains($0) }) else { return true }
            hints[key(for: parts)] = category
            for part in parts where hints[part] == nil { hints[part] = category }
            return true
        }
        #endif
        return hints
    }
}

// MARK: - Reguljära uttryck

struct TextPattern: @unchecked Sendable {
    let expression: NSRegularExpression

    init(_ pattern: String, caseInsensitive: Bool = false) {
        // Mönstren är konstanta och testade; ett fel här är ett programmeringsfel.
        expression = try! NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
    }

    func matches(in text: String, group: Int = 0) -> [Range<String.Index>] {
        expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            Range(match.range(at: group), in: text)
        }
    }

    /// Första träffen som börjar exakt i början av `range`.
    func firstMatch(in text: String, range: Range<String.Index>) -> Range<String.Index>? {
        guard let match = expression.firstMatch(in: text, options: [.anchored], range: NSRange(range, in: text)) else {
            return nil
        }
        return Range(match.range, in: text)
    }
}

enum Patterns {
    static let email = TextPattern(
        #"(?<![\p{L}\p{N}._%+-])[\p{L}\p{N}._%+-]+(?:\s?@\s?|\s+snabel-a\s+)[\p{L}\p{N}-]+(?:(?:\.|\s+(?:punkt|dot)\s+)[\p{L}\p{N}-]+)+"#,
        caseInsensitive: true
    )
    static let iban = TextPattern(#"(?<![\p{L}\p{N}])[A-Z]{2}\d{2}(?: ?[A-Z0-9]{4}){3,7}(?: ?[A-Z0-9]{1,3})?(?![\p{L}\p{N}])"#)
    static let personalNumber = TextPattern(#"(?<![\d+])(?:19|20)?\d{6}(?:\s?[-+–]\s?|\s)?\d{4}(?!\d)"#)
    static let cardNumber = TextPattern(#"(?<![\d+])\d(?:[ -]?\d){12,18}(?!\d)"#)
    static let accountWithContext = TextPattern(
        #"(?<![\p{L}])(?:bankgiro|plusgiro|bg|pg|konto|kontot|kontonummer|kontonumret|kontonr|bankkonto|bankkontot|clearing|clearingnummer|clearingnumret|iban|swish)(?:nummer|numret|t)?(?![\p{L}])[^\d\n]{0,20}?(\d[\d ,.-]{3,30}\d)"#,
        caseInsensitive: true
    )
    static let swedishPhone = TextPattern(#"(?<![\d+])(?:\+46|0046|0)[\s-]?(?:\(0\)[\s-]?)?[1-9](?:[\s-]?\d){5,9}(?!\d)"#)
    static let internationalPhone = TextPattern(#"(?<![\d+])(?:\+|00)[1-9]\d{0,2}(?:[\s-]?\d){6,12}(?!\d)"#)
    /// Svenska regnummer: tre bokstäver (ej I, Q, V, Å, Ä, Ö) och två siffror plus en siffra eller bokstav.
    static let licensePlate = TextPattern(#"(?<![\p{L}\p{N}])[A-HJ-PR-UW-Z]{3}[ -]?\d{2}[A-HJ-PR-UW-Z0-9](?![\p{L}\p{N}])"#)
    static let streetAddress = TextPattern(
        #"(?<![\p{L}])\p{Lu}[\p{L}-]*(?:gatan|gata|vägen|väg|gränden|gränd|torget|torg|backen|backe|stigen|stig|allén|allé|leden|platsen|plan|esplanaden|kajen|stranden|strand)(?: nummer)? +\d{1,4}(?: ?[A-Za-z](?![\p{L}]))?(?:,? *(?:lgh|lägenhet) *\d+)?(?:,? +\d{3} ?\d{2}(?: +\p{Lu}[\p{L}-]+)?)?"#
    )
    static let postalCode = TextPattern(#"(?<![\d+])\d{3} \d{2}(?= +\p{Lu}\p{Ll})"#)

    static let sensitive: [(AnonymizationCategory, TextPattern)] = [
        (.health, wordList([
            #"cancer\p{L}*"#, #"tumör\p{L}*"#, #"diabet\p{L}*"#, #"depression\p{L}*"#, #"deprimerad\p{L}*"#,
            #"ångestsyndrom\p{L}*"#, #"panikångest\p{L}*"#, "adhd", #"autism\p{L}*"#, #"autistisk\p{L}*"#,
            #"asperger\p{L}*"#, "hiv", "aids", #"epilepsi\p{L}*"#, #"schizofren\p{L}*"#, #"bipolär\p{L}*"#,
            #"psykos\p{L}*"#, #"utbrändhet\p{L}*"#, #"utbränd\p{L}*"#, #"utmattningssyndrom\p{L}*"#,
            #"utmattningsdepression\p{L}*"#, #"sjukskriv\p{L}*"#, #"missbruk\p{L}*"#, #"alkoholis\p{L}*"#,
            #"demens\p{L}*"#, #"alzheimer\p{L}*"#, #"parkinson\p{L}*"#, #"gravid\p{L}*"#, #"missfall\p{L}*"#,
            #"abort\p{L}*"#, #"självmord\p{L}*"#, #"anorexi\p{L}*"#, #"bulimi\p{L}*"#, #"ätstörning\p{L}*"#,
            "stroke", #"hjärtinfarkt\p{L}*"#, #"astma\p{L}*"#, #"allergi\p{L}*"#, #"antidepressiv\p{L}*"#,
            #"cellgift\p{L}*"#, "cytostatika", #"kemoterapi\p{L}*"#, #"funktionsnedsättning\p{L}*"#,
            #"funktionshinder\p{L}*"#, #"dyslexi\p{L}*"#, #"covid\p{L}*"#
        ])),
        (.religion, wordList([
            #"muslim\p{L}*"#, #"islam\p{L}*"#, "kristen", "kristna", #"kristendom\p{L}*"#, "jude", #"judar\p{L}*"#,
            #"judisk\p{L}*"#, #"judendom\p{L}*"#, #"katolik\p{L}*"#, #"katolsk\p{L}*"#, #"buddhist\p{L}*"#,
            #"buddhism\p{L}*"#, #"hindu\p{L}*"#, #"ateist\p{L}*"#, #"frikyrk\p{L}*"#, #"pingstvän\p{L}*"#,
            #"jehovas vittne\p{L}*"#, #"moské\p{L}*"#, #"synagog\p{L}*"#, "ramadan"
        ])),
        (.politics, wordList([
            #"socialdemokrat\p{L}*"#, "sosse", #"sossar\p{L}*"#, "moderaterna", #"moderatväljare\p{L}*"#,
            #"sverigedemokrat\p{L}*"#, #"vänsterpartist\p{L}*"#, "vänsterpartiet", #"miljöpartist\p{L}*"#,
            "miljöpartiet", #"centerpartist\p{L}*"#, "centerpartiet", "liberalerna", #"kristdemokrat\p{L}*"#,
            #"kommunist\p{L}*"#, #"nazist\p{L}*"#
        ])),
        (.sexuality, wordList([
            #"homosexu\p{L}*"#, #"bisexu\p{L}*"#, #"lesbisk\p{L}*"#, "gay", #"bög\p{L}*"#, #"hbtq\p{L}*"#,
            #"transperson\p{L}*"#, "queer"
        ])),
        (.tradeUnion, wordList([
            #"fackmedlem\p{L}*"#, #"fackansluten\p{L}*"#, "fackanslutna", "medlem i facket"
        ]))
    ]

    private static func wordList(_ alternatives: [String]) -> TextPattern {
        TextPattern(#"(?<![\p{L}\p{N}])(?:"# + alternatives.joined(separator: "|") + #")(?![\p{L}\p{N}])"#, caseInsensitive: true)
    }
}

extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
