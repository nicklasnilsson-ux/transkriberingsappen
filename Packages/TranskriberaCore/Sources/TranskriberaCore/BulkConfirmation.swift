import Foundation

/// Bevis för att användaren har bekräftat att flera transkriberingar raderas.
/// Kön raderar bara tillsammans med det här värdet; utan bekräftelse (eller utan något att
/// radera) returnerar initieraren `nil`, så en radering utan fråga kompilerar inte.
public struct DeleteConfirmation: Sendable {
    public let count: Int

    public init?(count: Int, confirmed: Bool) {
        guard count > 0, confirmed else { return nil }
        self.count = count
    }

    public static func title(count: Int) -> String {
        count == 1 ? "Radera 1 transkribering?" : "Radera \(count) transkriberingar?"
    }

    public static func message(count: Int) -> String {
        let what = count == 1 ? "Texten och appens kopia av filen" : "Texten och appens kopior av filerna"
        return "\(what) raderas för alla \(count) valda. Originalfilerna påverkas inte. Det går inte att ångra."
    }
}

/// Texter för "Transkribera N igen". Bekräftelsen själv är `RetranscribeConfirmation`.
public enum BulkRetranscribe {
    public static func title(count: Int) -> String {
        "Transkribera \(count) igen?"
    }

    /// `atCapacity`: hur många av de valda som redan har alla platser för versioner använda.
    public static func message(count: Int, atCapacity: Int = 0) -> String {
        var text = "Den nuvarande versionen av varje text sparas, med rättningar och talarnamn. Appen behåller de \(VersionHistory.capacity) senaste versionerna per transkribering. Gäller alla \(count) valda."
        if atCapacity == 1 {
            text += " 1 av dem har redan \(VersionHistory.capacity) versioner, så dess äldsta version raderas när den nya är klar."
        } else if atCapacity > 1 {
            text += " \(atCapacity) av dem har redan \(VersionHistory.capacity) versioner, så deras äldsta versioner raderas när de nya är klara."
        }
        return text
    }

    public static func buttonTitle(count: Int) -> String { "Transkribera \(count) igen…" }
}
