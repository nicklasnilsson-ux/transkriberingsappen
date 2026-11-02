import Foundation

/// Bevis för att användaren har bekräftat att "Transkribera igen" får ersätta texten.
/// "Transkribera igen" ersätter den visade texten med en ny version. Den förra sparas, men
/// den äldsta raderas när alla platser används (se `VersionHistory`), så kön tar bara emot en
/// omtagning tillsammans med det här värdet. Det går inte att skapa utan bekräftelse (initieraren
/// returnerar `nil`), så en omtagning som skriver över text utan att fråga kompilerar inte.
public struct RetranscribeConfirmation: Sendable {
    /// - Parameters:
    ///   - hasText: finns det text (rättningar, talarnamn) som skrivs över?
    ///   - confirmed: har användaren bekräftat i dialogen (eller stängt av dialogen i
    ///     Inställningar, vilket bara går när inget raderas, se `RetranscribeDialog`)?
    /// Utan text finns inget att förlora, då behövs ingen bekräftelse (t.ex. "Försök igen"
    /// efter ett misslyckande).
    public init?(replacingText hasText: Bool, confirmed: Bool) {
        guard !hasText || confirmed else { return nil }
    }
}
