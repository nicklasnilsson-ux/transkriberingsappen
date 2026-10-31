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
        // Första omgången (13 körningar, v0.6.0) visade att spärrar och omkörningar inte spelar roll.
        // Nu provas ledtråd för fyllnadsord, eftersom KB-Whisper rensar bort eh och mm helt.
        let list = "Eh, öh, mm, ja, jaha, alltså, liksom."
        let text = "Eh, ja alltså, det är ju så att, mm, vi har liksom, öh, ja precis. Mm, jaha, nej men eh, det stämmer."
        return [
            kb("01-kb-referens", "KB: som i dag"),
            kb("02-kb-fyllnadslista", "KB: ledtråd med fyllnadsord som lista") { $0.stylePrompt = list },
            kb("03-kb-fyllnadstext", "KB: ledtråd med fyllnadsord i löpande text") { $0.stylePrompt = text },
            kb("04-kb-fyllnadstext-huvudpass", "KB: ledtråd i löpande text, bara i huvudpasset") {
                $0.stylePrompt = text
                $0.stylePromptInGapCheck = false
            },
            pianissimo("05-pianissimo-referens", "Pianissimo: som i dag")
        ]
    }()
}
