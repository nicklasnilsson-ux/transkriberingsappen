import Foundation

/// En körning i Testlabbet: en modell med en uppsättning inställningar.
public struct TestLabRun: Codable, Hashable, Identifiable, Sendable {
    public enum Engine: String, Codable, Sendable {
        case kbLargeStrict
        case pianissimo

        public var title: String {
            switch self {
            case .kbLargeStrict: return "KB Large ordagrann"
            case .pianissimo: return "Pianissimo"
            }
        }
    }

    /// Kort namn som också blir början på filnamnen, t.ex. "03-kb-utan-upprepningssparr".
    public var id: String
    public var title: String
    public var engine: Engine
    public var tuning: DecoderTuning
    public var levelVolume: Bool
    public var carefulSeams: Bool

    public init(
        id: String,
        title: String,
        engine: Engine,
        tuning: DecoderTuning = .production,
        levelVolume: Bool = true,
        carefulSeams: Bool = false
    ) {
        self.id = id
        self.title = title
        self.engine = engine
        self.tuning = tuning
        self.levelVolume = levelVolume
        self.carefulSeams = carefulSeams
    }

    /// Det som skiljer från en vanlig transkribering med samma modell, i klartext.
    public var differences: [String] {
        var out = tuning.differences
        if engine == .pianissimo, carefulSeams { out.append("noggrannare skarvar") }
        if engine == .kbLargeStrict, !levelVolume { out.append("volymutjämning av") }
        return out
    }
}

public enum TestLabPlan {
    /// Listan som körs som standard. Varje körning ändrar en sak mot referensen, utom de
    /// som uttryckligen kombinerar. Referensen körs två gånger för att mäta bruset.
    public static let standard: [TestLabRun] = {
        func kb(_ id: String, _ title: String, _ change: (inout DecoderTuning) -> Void = { _ in }) -> TestLabRun {
            var tuning = DecoderTuning.production
            change(&tuning)
            return TestLabRun(id: id, title: title, engine: .kbLargeStrict, tuning: tuning)
        }
        func pianissimo(_ id: String, _ title: String, carefulSeams: Bool = false,
                        _ change: (inout DecoderTuning) -> Void = { _ in }) -> TestLabRun {
            var tuning = DecoderTuning.production
            change(&tuning)
            return TestLabRun(id: id, title: title, engine: .pianissimo, tuning: tuning, carefulSeams: carefulSeams)
        }
        return [
            kb("01-kb-referens", "KB: som i dag"),
            kb("02-kb-referens-igen", "KB: som i dag, igen (mäter bruset)"),
            kb("03-kb-utan-upprepningssparr", "KB: utan upprepningsspärr") { $0.compressionRatioThreshold = nil },
            kb("04-kb-utan-osakerhetssparr", "KB: utan osäkerhetsspärr") { $0.logProbThreshold = nil },
            kb("05-kb-utan-bada-sparrarna", "KB: utan båda spärrarna") {
                $0.compressionRatioThreshold = nil
                $0.logProbThreshold = nil
            },
            kb("06-kb-utan-fonsterklipp", "KB: utan fönsterklipp") { $0.windowClipTime = 0 },
            kb("07-kb-utan-omkorningar", "KB: utan omkörningar med slump") { $0.temperatureFallbackCount = 0 },
            kb("08-kb-utan-luckkontroll", "KB: utan luckkontroll") { $0.repairsGaps = false },
            kb("09-kb-allt-lost", "KB: utan spärrar och fönsterklipp") {
                $0.compressionRatioThreshold = nil
                $0.logProbThreshold = nil
                $0.windowClipTime = 0
            },
            pianissimo("10-pianissimo-referens", "Pianissimo: som i dag"),
            pianissimo("11-pianissimo-fler-bitar", "Pianissimo: fler textbitar per fönster") { $0.maxTokensPerChunk = 300 },
            pianissimo("12-pianissimo-tatare-skarvlagning", "Pianissimo: lagar mindre luckor vid skarvar") {
                $0.seamGapRepairMinGapSeconds = 0.5
            },
            pianissimo("13-pianissimo-noggranna-skarvar", "Pianissimo: noggrannare skarvar", carefulSeams: true)
        ]
    }()
}
