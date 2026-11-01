import Foundation

/// Grupperna i sidopanelens lista över transkriberingar.
public enum SidebarGroup: String, CaseIterable, Sendable {
    case today = "Idag"
    case lastWeek = "Senaste veckan"
    case earlier = "Tidigare"

    /// Idag = samma kalenderdag, Senaste veckan = mindre än 7 dygn, annars Tidigare.
    public static func group(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> SidebarGroup {
        if calendar.isDate(date, inSameDayAs: now) { return .today }
        let start = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        if let days = calendar.dateComponents([.day], from: start, to: today).day, days >= 0, days < 7 {
            return .lastWeek
        }
        return .earlier
    }
}
