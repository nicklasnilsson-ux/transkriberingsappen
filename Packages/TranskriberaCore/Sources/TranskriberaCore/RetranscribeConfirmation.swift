import Foundation

/// Bevis för att användaren har bekräftat att "Transkribera igen" får ersätta texten.
/// "Transkribera igen" raderar rättningar och talarnamn, så kön tar bara emot en omtagning
/// tillsammans med det här värdet. Det går inte att skapa utan bekräftelse (initieraren
/// returnerar `nil`), så en omtagning som skriver över text utan att fråga kompilerar inte.
public struct RetranscribeConfirmation: Sendable {
    /// - Parameters:
    ///   - hasText: finns det text (rättningar, talarnamn) som skrivs över?
    ///   - confirmed: har användaren bekräftat i dialogen?
    /// Utan text finns inget att förlora, då behövs ingen bekräftelse (t.ex. "Försök igen"
    /// efter ett misslyckande).
    public init?(replacingText hasText: Bool, confirmed: Bool) {
        guard !hasText || confirmed else { return nil }
    }

    public static let dialogMessage = "Rättningar och talarnamn ersätts. Det går inte att ångra."
}
