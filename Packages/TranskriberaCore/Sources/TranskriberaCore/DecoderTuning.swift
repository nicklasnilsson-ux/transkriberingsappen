import Foundation

/// Justeringar av taligenkänningen som Testlabbet kan ändra per körning.
///
/// Standardvärdet är exakt det appen använder i vanliga transkriberingar (kontrolleras av
/// `DecoderTuningTests`), så att labbet inte ändrar något utanför sig själv. Värdena är
/// lästa ur WhisperKit 1.1.1 (`DecodingOptions`) och FluidAudio 0.17.7 (`ASRConfig`, `TdtConfig`).
public struct DecoderTuning: Codable, Hashable, Sendable {
    // MARK: KB-Whisper (WhisperKit)

    /// Text som komprimeras bättre än så här räknas som upprepning och körs om med mer slump.
    /// `nil` = ingen spärr.
    public var compressionRatioThreshold: Float? = 2.4
    /// Text där modellen i snitt är osäkrare än så här körs om med mer slump. `nil` = ingen spärr.
    public var logProbThreshold: Float? = -1.0
    /// Sekunder i slutet av varje 30-sekundersfönster som inte avkodas (mot påhittad text).
    public var windowClipTime: Float = 1.0
    /// Hur många gånger en underkänd text får köras om med mer slump.
    public var temperatureFallbackCount = 3
    /// Tal som saknar text efter körningen transkriberas om för sig (`repairGaps`).
    public var repairsGaps = true
    /// Ledtråd i Whispers språk (en text "före" ljudet) som visar stilen: ordagrant med
    /// "eh" och "mm". `nil` = ingen ledtråd, som i dag.
    public var stylePrompt: String?
    /// Om ledtråden också gäller luckkontrollens omkörningar (annars bara huvudpasset).
    public var stylePromptInGapCheck = true

    // MARK: Pianissimo (FluidAudio)

    /// Minsta lucka (sekunder) mellan ord vid en fönsterskarv som repareras. FluidAudio
    /// tillåter inte under 0,5.
    public var seamGapRepairMinGapSeconds: Double = 1.5
    /// Högsta antal textbitar per 15-sekundersfönster. Fler än så klipps bort.
    public var maxTokensPerChunk = 150

    public init() {}

    /// Det appen använder i vanliga transkriberingar.
    public static let production = DecoderTuning()

    /// Det som skiljer från vanliga transkriberingar, i klartext. Tomt = inget.
    public var differences: [String] {
        let standard = DecoderTuning.production
        var out: [String] = []
        if compressionRatioThreshold != standard.compressionRatioThreshold {
            out.append("upprepningsspärr \(Self.describe(compressionRatioThreshold))")
        }
        if logProbThreshold != standard.logProbThreshold {
            out.append("osäkerhetsspärr \(Self.describe(logProbThreshold))")
        }
        if windowClipTime != standard.windowClipTime { out.append("fönsterklipp \(windowClipTime) s") }
        if temperatureFallbackCount != standard.temperatureFallbackCount {
            out.append("omkörningar \(temperatureFallbackCount)")
        }
        if repairsGaps != standard.repairsGaps { out.append(repairsGaps ? "luckkontroll på" : "luckkontroll av") }
        if stylePrompt != standard.stylePrompt {
            out.append("ledtråd \"\(stylePrompt ?? "av")\"")
            if !stylePromptInGapCheck { out.append("ledtråden bara i huvudpasset") }
        }
        if seamGapRepairMinGapSeconds != standard.seamGapRepairMinGapSeconds {
            out.append("skarvlagning från \(seamGapRepairMinGapSeconds) s")
        }
        if maxTokensPerChunk != standard.maxTokensPerChunk { out.append("max \(maxTokensPerChunk) bitar per fönster") }
        return out
    }

    private static func describe(_ value: Float?) -> String {
        value.map { "\($0)" } ?? "av"
    }
}
