import Foundation

/// När titelkortet fälls ihop till en rad som ligger kvar överst. Med hysteres så att
/// raden inte flimrar: den fälls ihop först vid 260 pt skrollat och ut igen först under 200 pt.
public enum TitleCardCollapse {
    public static let collapseAt: Double = 260
    public static let expandBelow: Double = 200

    public static func isCollapsed(offset: Double, wasCollapsed: Bool) -> Bool {
        if wasCollapsed { return offset >= expandBelow }
        return offset > collapseAt
    }
}
