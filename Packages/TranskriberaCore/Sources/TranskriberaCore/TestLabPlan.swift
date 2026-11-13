import Foundation

/// En körning i Testlabbet: en modell med en uppsättning inställningar.
public struct TestLabRun: Codable, Hashable, Identifiable, Sendable {
    public enum Engine: String, CaseIterable, Codable, Sendable {
        case kbLargeStrict
        case pianissimo
        case largeV3Turbo
        /// Test 2026-11-13: Pianissimo med kodaren i 16 bitar i stället för 8.
        case pianissimoFP16
        /// Test 2026-11-13: Pianissimo i 32 bitar, som originalet.
        case pianissimoFP32

        public var title: String {
            switch self {
            case .kbLargeStrict: return "KB Large ordagrann"
            case .pianissimo: return "Pianissimo"
            case .largeV3Turbo: return "Large v3 Turbo"
            case .pianissimoFP16: return "Pianissimo 16 bitar"
            case .pianissimoFP32: return "Pianissimo 32 bitar"
            }
        }

        /// Sant för alla Pianissimo-varianter.
        public var isPianissimo: Bool { self == .pianissimo || self == .pianissimoFP16 || self == .pianissimoFP32 }

        /// Sant för modellerna i modellväljaren. Precisionstesterna finns bara i Testlabbets
        /// precisionslista och hör inte hemma i tidsmätningen.
        public var isInModelPicker: Bool { self != .pianissimoFP16 && self != .pianissimoFP32 }
    }

    /// Hur talarna tas fram i körningen.
    public enum Speakers: String, Codable, Sendable {
        /// Talarna identifieras en gång före alla körningar och används i alla, så att
        /// skillnaderna bara kommer från taligenkänningen. Gäller om talare är på i inställningarna.
        case shared
        /// Inga talare, som när talaridentifieringen är av.
        case none
        /// Talarna identifieras i körningen, som i en vanlig transkribering, och tiden mäts.
        case own
    }

    /// Kort namn som också blir början på filnamnen, t.ex. "03-kb-utan-upprepningssparr".
    public var id: String
    public var title: String
    public var engine: Engine
    public var tuning: DecoderTuning
    public var levelVolume: Bool
    public var carefulSeams: Bool
    public var speakers: Speakers
    /// Experiment "Korskolla": hela ljudet körs också med KB Large ordagrann och skillnaderna i
    /// innebördsord markeras (`CrossCheck`). Bara Pianissimo.
    public var crossCheck: Bool

    public init(
        id: String,
        title: String,
        engine: Engine,
        tuning: DecoderTuning = .production,
        levelVolume: Bool = true,
        carefulSeams: Bool = false,
        speakers: Speakers = .shared,
        crossCheck: Bool = false
    ) {
        self.id = id
        self.title = title
        self.engine = engine
        self.tuning = tuning
        self.levelVolume = levelVolume
        self.carefulSeams = carefulSeams
        self.speakers = speakers
        self.crossCheck = crossCheck
    }

    /// Det som skiljer från en vanlig transkribering med samma modell, i klartext.
    public var differences: [String] {
        var out = tuning.differences
        if engine.isPianissimo, carefulSeams { out.append("noggrannare skarvar") }
        if engine == .pianissimoFP16 { out.append("kodaren i 16 bitar i stället för 8") }
        if engine == .pianissimoFP32 { out.append("hela modellen i 32 bitar") }
        if engine == .kbLargeStrict, !levelVolume { out.append("volymutjämning av") }
        if crossCheck { out.append("korskollad med KB Large") }
        switch speakers {
        case .shared: break
        case .none: out.append("utan talare")
        case .own: out.append("med talare")
        }
        return out
    }
}

public enum TestLabPlan {
    /// Listorna som går att välja i Testlabbet.
    public enum Kind: String, CaseIterable, Identifiable, Sendable {
        case comparison
        case timing
        case precision
        case crossCheck

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .comparison: return "Jämför inställningar"
            case .timing: return "Tidsmätning"
            case .precision: return "Pianissimo: 8, 16 och 32 bitar"
            case .crossCheck: return "Korskolla med KB Large"
            }
        }

        public var runs: [TestLabRun] {
            switch self {
            case .comparison: return TestLabPlan.standard
            case .timing: return TestLabPlan.timing
            case .precision: return TestLabPlan.precision
            case .crossCheck: return TestLabPlan.crossCheck
            }
        }
    }

    /// Hur lång tid hela kedjan tar med varje modell i väljaren, med och utan talare.
    /// Inställningarna är som i en vanlig transkribering; bara modellen och talarna skiljer.
    /// Talarna identifieras i varje körning med talare, så att den tiden kommer med.
    public static let timing: [TestLabRun] = [
        TestLabRun(id: "01-pianissimo-utan-talare", title: "Pianissimo utan talare", engine: .pianissimo, speakers: .none),
        TestLabRun(id: "02-pianissimo-med-talare", title: "Pianissimo med talare", engine: .pianissimo, speakers: .own),
        TestLabRun(id: "03-kb-utan-talare", title: "KB Large ordagrann utan talare", engine: .kbLargeStrict, speakers: .none),
        TestLabRun(id: "04-kb-med-talare", title: "KB Large ordagrann med talare", engine: .kbLargeStrict, speakers: .own),
        TestLabRun(id: "05-turbo-utan-talare", title: "Large v3 Turbo utan talare", engine: .largeV3Turbo, speakers: .none),
        TestLabRun(id: "06-turbo-med-talare", title: "Large v3 Turbo med talare", engine: .largeV3Turbo, speakers: .own)
    ]

    /// Samma Pianissimo med olika precision (2026-11-13). Den vanliga har kodaren förminskad
    /// till 8 bitar. Klangs kort (danska, 38 min) mäter Core ML 8 och 16 bitar
    /// lika (6,9 och 7,0 % mot 6,5 i original); 32 bitar i Core ML är omätt. Allt annat är som en vanlig transkribering.
    public static let precision: [TestLabRun] = [
        TestLabRun(id: "01-pianissimo-8-bitar", title: "Pianissimo som i dag (kodaren i 8 bitar)", engine: .pianissimo),
        TestLabRun(id: "02-pianissimo-16-bitar", title: "Pianissimo 16 bitar", engine: .pianissimoFP16),
        TestLabRun(id: "03-pianissimo-32-bitar", title: "Pianissimo 32 bitar", engine: .pianissimoFP32)
    ]

    /// Experimentet "Korskolla" (2026-11-13). Pianissimo körs som vanligt, KB Large ordagrann lyssnar
    /// en gång till, och skillnaderna i innebördsord sparas som en lista (`-korskoll.txt`) att gå
    /// igenom med ljudet. Bara KB Large som andra lyssnare (beslut Nicklas).
    public static let crossCheck: [TestLabRun] = [
        TestLabRun(id: "01-pianissimo-korskollad", title: "Pianissimo, korskollad med KB Large", engine: .pianissimo, crossCheck: true)
    ]

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
