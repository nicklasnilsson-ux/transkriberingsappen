import AppKit
import SwiftData
import SwiftUI
import XCTest
import TranskriberaCore
@testable import Transkribera

/// Mäter att ett stycke och en rad har exakt samma höjd i visnings- och redigeringsläget.
/// Skiljer höjden hoppar texten när man trycker på Redigera (se docs/KONTROLLER.md).
/// Texterna är påhittade.
@MainActor
final class EditModeHeightTests: XCTestCase {
    private let texts = [
        "Jag börjar oftast dagen med att gå igenom ärendena som kommit in under natten.",
        "Sedan tar jag de akuta, och resten får vänta till efter lunch när det är lugnare.",
        "Efter lunch blir det möten med kollegorna, ibland ganska långa och ibland korta.",
        "Det viktigaste är att ingen behöver vänta på svar längre än en dag.",
    ]
    /// Högst så här mycket skillnad (punkter) räknas som samma höjd.
    private let tolerance: CGFloat = 0.5

    private var container: ModelContainer!
    private var savedSize: Any?

    override func setUp() async throws {
        container = try ModelContainer(
            for: Transcript.self, TranscriptSegment.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        savedSize = UserDefaults.standard.object(forKey: SettingsKey.readingTextSize)
    }

    override func tearDown() async throws {
        UserDefaults.standard.set(savedSize, forKey: SettingsKey.readingTextSize)
        container = nil
    }

    private func makeRows() -> [DisplaySegment] {
        let context = container.mainContext
        return texts.enumerated().map { index, text in
            let segment = TranscriptSegment(
                index: index,
                data: SegmentData(start: Double(index) * 5, end: Double(index) * 5 + 5, text: text, speaker: "Anna")
            )
            context.insert(segment)
            return DisplaySegment(segment: segment, text: text, speaker: "Anna")
        }
    }

    /// Ritar vyn i ett fönster utanför skärmen med fast bredd och returnerar höjden.
    private func height<V: View>(of view: V, width: CGFloat = 900) -> CGFloat {
        let host = NSHostingView(rootView: view.frame(width: width).fixedSize(horizontal: false, vertical: true))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 2000),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        // Ett varv i körloopen, så att textfälten hinner mäta sin text.
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize.height
        window.contentView = nil
        return size
    }

    func testParagraphHasSameHeightInBothModes() {
        let rows = makeRows()
        for size in ReadingTextSize.steps {
            UserDefaults.standard.set(size, forKey: SettingsKey.readingTextSize)
            func row(_ editing: Bool) -> some View {
                ParagraphRow(rows: rows, query: "", activeID: nil, currentTime: nil, isEditing: editing, onSeek: { _ in })
            }
            let viewing = height(of: row(false))
            let editing = height(of: row(true))
            print("Stycke \(size) pt: visning \(viewing), redigering \(editing)")
            XCTAssertGreaterThan(viewing, size * 3, "Stycket ska vara flera rader högt vid \(size) pt")
            XCTAssertEqual(viewing, editing, accuracy: tolerance, "Stycket byter höjd vid \(size) pt")
        }
    }

    func testRowHasSameHeightInBothModes() {
        let rows = makeRows()
        for size in ReadingTextSize.steps {
            UserDefaults.standard.set(size, forKey: SettingsKey.readingTextSize)
            for segment in rows.map(\.segment) {
                func row(_ editing: Bool) -> some View {
                    SegmentRow(
                        segment: segment, displayText: segment.text, displaySpeaker: "Anna", query: "",
                        isActive: false, currentTime: nil, isEditing: editing, onSeek: {}
                    )
                }
                // Smal bredd, så att raderna bryts.
                let viewing = height(of: row(false), width: 420)
                let editing = height(of: row(true), width: 420)
                print("Rad \(segment.index) \(size) pt: visning \(viewing), redigering \(editing)")
                XCTAssertEqual(viewing, editing, accuracy: tolerance, "Rad \(segment.index) byter höjd vid \(size) pt")
            }
        }
    }
}
