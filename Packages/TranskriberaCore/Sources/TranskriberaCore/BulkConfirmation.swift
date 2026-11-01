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

    public static func message(count: Int) -> String {
        "\(RetranscribeConfirmation.dialogMessage) Gäller alla \(count) valda."
    }

    public static func buttonTitle(count: Int) -> String { "Transkribera \(count) igen…" }
}
