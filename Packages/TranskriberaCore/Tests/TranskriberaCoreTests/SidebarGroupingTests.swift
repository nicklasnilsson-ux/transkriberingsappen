import XCTest
@testable import TranskriberaCore

final class SidebarGroupingTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        return f.date(from: s)!
    }

    func testGroups() {
        let now = date("2026-11-01T12:00:00Z")
        func group(_ s: String) -> SidebarGroup { SidebarGroup.group(for: date(s), now: now, calendar: calendar) }
        XCTAssertEqual(group("2026-11-01T00:05:00Z"), .today)
        XCTAssertEqual(group("2026-10-31T23:59:00Z"), .lastWeek)
        XCTAssertEqual(group("2026-10-26T08:00:00Z"), .lastWeek)
        XCTAssertEqual(group("2026-10-25T08:00:00Z"), .earlier)
        XCTAssertEqual(group("2026-01-01T08:00:00Z"), .earlier)
    }

    func testFutureDateDoesNotCrashAndCountsAsEarlier() {
        let now = date("2026-11-01T12:00:00Z")
        XCTAssertEqual(SidebarGroup.group(for: date("2026-11-05T12:00:00Z"), now: now, calendar: calendar), .earlier)
    }

    func testTitlesAreTheSwedishLabels() {
        XCTAssertEqual(SidebarGroup.allCases.map(\.rawValue), ["Idag", "Senaste veckan", "Tidigare"])
    }
}
