import AppKit
import SwiftUI
import XCTest
import TranskriberaCore
@testable import Transkribera

/// Inställningskortet överst i sidopanelen ritas på riktigt i olika bredder. Varje rad ska vara en rad även
/// i den smalaste panelen: kortet får inte bli högre när panelen blir smalare. Felet 2026-11-05: väljarna för
/// ny transkribering i huvudytan trycktes ihop när fönstret var smalt och orden bröts på flera rader.
@MainActor
final class SettingsCardTests: XCTestCase {
    private func height(of summary: NextTranscriptionSummary, width: CGFloat) -> CGFloat {
        let host = NSHostingView(rootView: SettingsCardLabel(summary: summary).frame(width: width))
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.height
    }

    func testCardDoesNotGrowWhenTheSidebarIsNarrow() {
        let long = NextTranscriptionSummary(modelName: "Large v3 Turbo (andra språk)", languageName: "Automatiskt språk",
                                            identifySpeakers: true, hasVocabulary: true, modelDownloaded: false)
        let short = NextTranscriptionSummary(modelName: "Pianissimo", languageName: "Svenska",
                                             identifySpeakers: false, hasVocabulary: false, modelDownloaded: true)
        // 220 pt är sidopanelens minsta bredd; kortet har 2 × marginal inuti listan.
        let narrow = height(of: long, width: 190)
        let wide = height(of: long, width: 400)
        XCTAssertGreaterThan(wide, 20, "kortet ritades inte")
        XCTAssertEqual(narrow, wide, accuracy: 0.5, "en rad i kortet bröts i smal panel (\(narrow) mot \(wide) pt)")
        // Utan andra rad är kortet lägre: raden visas bara när något är på.
        XCTAssertLessThan(height(of: short, width: 190), narrow)
    }
}
