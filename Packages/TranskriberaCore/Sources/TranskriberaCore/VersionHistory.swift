import Foundation

/// En version av texten (den som visas eller en sparad), så som reglerna nedan räknar med den.
public struct VersionSlot: Equatable, Sendable {
    public var id: UUID
    /// När versionen blev klar.
    public var date: Date

    public init(id: UUID, date: Date) {
        self.id = id
        self.date = date
    }
}

/// Reglerna för sparade versioner av en transkribering. "Transkribera igen" sparar den förra
/// versionen (med rättningar och talarnamn) i stället för att skriva över den, och appen
/// behåller de `capacity` senaste, den som visas inräknad. Äldre raderas.
public enum VersionHistory {
    public static let capacity = 4

    /// Versionerna i tidsordning, äldst först. Lika tid avgörs av id, så att ordningen är stabil.
    public static func ordered(_ slots: [VersionSlot]) -> [VersionSlot] {
        slots.sorted { ($0.date, $0.id.uuidString) < ($1.date, $1.id.uuidString) }
    }

    /// Vilka sparade versioner som ska raderas när en ny version läggs till: alltid de äldsta,
    /// aldrig den nya. `existing` är de sparade versionerna utan den nya.
    public static func idsToDrop(existing: [VersionSlot]) -> [UUID] {
        let room = capacity - 1
        let sorted = ordered(existing)
        guard sorted.count > room else { return [] }
        return sorted.prefix(sorted.count - room).map(\.id)
    }

    /// Versionens nummer (1 = äldst) och antalet versioner.
    public static func position(of id: UUID, in slots: [VersionSlot]) -> (number: Int, total: Int)? {
        let sorted = ordered(slots)
        guard let index = sorted.firstIndex(where: { $0.id == id }) else { return nil }
        return (index + 1, sorted.count)
    }

    /// Sant om `id` är den senaste versionen.
    public static func isLatest(_ id: UUID, in slots: [VersionSlot]) -> Bool {
        ordered(slots).last?.id == id
    }

    /// Etiketten i titelkortet, t.ex. "Version 2 av 4 · 14:32". Klockslaget står alltid med,
    /// eftersom numren räknas om när den äldsta raderas.
    public static func label(number: Int, total: Int, time: String) -> String {
        "Version \(number) av \(total) · \(time)"
    }
}

/// Texterna i dialogen för "Transkribera igen" och när den ska visas.
public enum RetranscribeDialog {
    public enum Kind: Equatable, Sendable {
        /// Det finns plats: den nuvarande versionen sparas.
        case roomLeft(versions: Int)
        /// Alla platser används: den äldsta versionen raderas.
        case replacesOldest
    }

    public static func kind(versionCount: Int) -> Kind {
        versionCount >= VersionHistory.capacity ? .replacesOldest : .roomLeft(versions: max(versionCount, 1))
    }

    /// Dialogen visas alltid när något raderas. Annars går den att stänga av i Inställningar.
    public static func needsDialog(versionCount: Int, askSetting: Bool) -> Bool {
        versionCount >= VersionHistory.capacity || askSetting
    }

    /// "Visa inte igen" erbjuds inte när något raderas.
    public static func canSuppress(_ kind: Kind) -> Bool {
        if case .roomLeft = kind { return true }
        return false
    }

    public static func title(_ kind: Kind) -> String {
        switch kind {
        case .roomLeft: "Transkribera igen?"
        case .replacesOldest: "Transkribera igen? Den äldsta versionen raderas"
        }
    }

    public static func message(_ kind: Kind) -> String {
        switch kind {
        case .roomLeft:
            "Den här versionen sparas, med dina rättningar och talarnamn. Du kan byta tillbaka med Version högst upp. Appen behåller de \(VersionHistory.capacity) senaste versionerna, och äldre raderas."
        case .replacesOldest:
            "Du har redan \(VersionHistory.capacity) versioner. De andra \(VersionHistory.capacity - 1) sparas, och du kan byta mellan dem med Version högst upp."
        }
    }

    /// Raden som säger vad som raderas, med den äldsta versionens tid och modell.
    public static func warning(oldest: String) -> String {
        "Raderas: Version 1 · \(oldest), med dess rättningar och talarnamn. Det går inte att ångra. Den raderas först när den nya versionen är klar."
    }

    public static func confirmButton(_ kind: Kind) -> String {
        switch kind {
        case .roomLeft: "Transkribera igen"
        case .replacesOldest: "Transkribera igen och radera Version 1"
        }
    }

    public static let suppressLabel = "Visa inte den här rutan igen"
    public static let suppressHint = "Du slår på den igen i Inställningar › Transkribering."
}

/// En sparad version av texten som data. Appen packar den innan den sparas i databasen.
public struct VersionSnapshot: Codable, Equatable, Sendable {
    public var segments: [SegmentData]

    public init(segments: [SegmentData]) {
        self.segments = segments
    }

    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    public static func decode(_ data: Data) throws -> VersionSnapshot {
        try JSONDecoder().decode(VersionSnapshot.self, from: data)
    }
}
