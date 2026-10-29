import Foundation

/// Hur många som pratar i en inspelning: ett exakt antal eller ett spann.
///
/// En intervju har minst två talare, så det automatiska valet säger "minst 2". Utan den
/// gränsen kan talaridentifieringen slå ihop intervjuaren och kunden till en talare.
public struct SpeakerCount: Hashable, Sendable, Identifiable {
    public var minimum: Int?
    public var maximum: Int?

    public init(minimum: Int?, maximum: Int?) {
        self.minimum = minimum
        self.maximum = maximum
    }

    public static func exactly(_ count: Int) -> SpeakerCount {
        SpeakerCount(minimum: count, maximum: count)
    }

    public static let automatic = SpeakerCount(minimum: 2, maximum: nil)

    /// Valen i appen. Spannen passar intervjuer med en intervjuare och 1–3 kunder.
    public static let choices: [SpeakerCount] = [
        .automatic,
        SpeakerCount(minimum: 2, maximum: 3),
        SpeakerCount(minimum: 2, maximum: 4)
    ] + (2...8).map { SpeakerCount.exactly($0) }

    /// Det exakta antalet, om det är känt.
    public var exact: Int? {
        guard let minimum, minimum == maximum else { return nil }
        return minimum
    }

    public var id: String { rawValue }

    public var label: String {
        if let exact { return "\(exact) talare" }
        switch (minimum, maximum) {
        case let (min?, max?): return "\(min)–\(max) talare"
        case let (min?, nil): return "Automatiskt, minst \(min)"
        case let (nil, max?): return "Automatiskt, högst \(max)"
        case (nil, nil): return "Automatiskt"
        }
    }
}

extension SpeakerCount: RawRepresentable {
    /// "auto", "3" eller "2-4". "min2" och "max4" för spann med bara en gräns.
    public var rawValue: String {
        if minimum == Self.automatic.minimum, maximum == Self.automatic.maximum { return "auto" }
        if let exact { return String(exact) }
        switch (minimum, maximum) {
        case let (min?, max?): return "\(min)-\(max)"
        case let (min?, nil): return "min\(min)"
        case let (nil, max?): return "max\(max)"
        case (nil, nil): return "any"
        }
    }

    public init?(rawValue: String) {
        let raw = rawValue.trimmingCharacters(in: .whitespaces)
        if raw == "auto" { self = .automatic; return }
        if raw == "any" { self.init(minimum: nil, maximum: nil); return }
        if raw.hasPrefix("min"), let min = Int(raw.dropFirst(3)), min > 0 {
            self.init(minimum: min, maximum: nil); return
        }
        if raw.hasPrefix("max"), let max = Int(raw.dropFirst(3)), max > 0 {
            self.init(minimum: nil, maximum: max); return
        }
        let parts = raw.split(separator: "-", omittingEmptySubsequences: false).map { Int($0) }
        switch parts.count {
        case 1:
            guard let count = parts[0], count > 0 else { return nil }
            self = .exactly(count)
        case 2:
            guard let min = parts[0], let max = parts[1], min > 0, min <= max else { return nil }
            self.init(minimum: min, maximum: max)
        default:
            return nil
        }
    }

    /// Den gamla inställningen var ett heltal: 0 = automatiskt, annars ett exakt antal.
    public init(legacyCount: Int) {
        self = legacyCount > 0 ? .exactly(legacyCount) : .automatic
    }
}
