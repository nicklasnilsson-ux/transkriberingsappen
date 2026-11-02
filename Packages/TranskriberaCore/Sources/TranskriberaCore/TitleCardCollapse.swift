import Foundation

/// När titelkortet fälls ihop till en rad som ligger kvar överst. Med hysteres så att
/// raden inte flimrar: den fälls ihop först vid 260 pt skrollat och ut igen först under 200 pt.
public enum TitleCardCollapse {
    public static let collapseAt: Double = 260
    public static let expandBelow: Double = 200

    /// `keepCollapsed`: raden får inte fällas ut, t.ex. medan sökfältet är öppet i den. Annars
    /// försvinner fältet mitt i skrivandet när en träff ligger nära toppen.
    public static func isCollapsed(offset: Double, wasCollapsed: Bool, keepCollapsed: Bool = false) -> Bool {
        if wasCollapsed { return keepCollapsed || offset >= expandBelow }
        return offset > collapseAt
    }
}
