import Foundation

/// Steget i en transkribering där något gick fel.
public enum FailureStep: String, Sendable, CaseIterable {
    case downloadModel
    case loadModel
    case prepareAudio
    case recognize
    case identifySpeakers

    public var label: String {
        switch self {
        case .downloadModel: return "Hämtar modellen"
        case .loadModel: return "Läser in modellen"
        case .prepareAudio: return "Läser in ljudet"
        case .recognize: return "Taligenkänning"
        case .identifySpeakers: return "Talarigenkänning"
        }
    }
}

/// Gör ett tekniskt fel begripligt: vilket steg det hände i, en trolig förklaring och
/// den tekniska texten kvar så att den går att kopiera. Förklaringen säger "trolig" där
/// orsaken är härledd och inte bekräftad.
public enum FailureExplainer {
    /// Datorer med mindre minne än så (8 GB-modellerna rapporterar 8 GiB) får modellerna
    /// frigjorda mellan stegen.
    public static let lowMemoryLimit: UInt64 = 12 * 1_073_741_824

    public static func isLowMemory(_ physicalMemory: UInt64) -> Bool {
        physicalMemory > 0 && physicalMemory < lowMemoryLimit
    }

    /// Core ML-fel där modellen inte gick att köra: det gäller både "Unable to compute the
    /// asynchronous prediction using ML Program" och slut på minne vid körning.
    public static func isModelComputeFailure(_ text: String) -> Bool {
        let lower = text.lowercased()
        return [
            "unable to compute", "ml program", "broken/unsupported model", "mlmodel",
            "failed to allocate", "out of memory", "insufficient memory", "espresso", "e5rt"
        ].contains { lower.contains($0) }
    }

    public static func gigabytes(_ bytes: UInt64) -> Int {
        Int((Double(bytes) / 1_073_741_824).rounded())
    }

    /// Texten som sparas på transkriberingen och visas i felrutan.
    public static func message(
        step: FailureStep,
        technical: String,
        physicalMemory: UInt64
    ) -> String {
        var parts = ["Det gick fel i steget ”\(step.label)”."]
        if isModelComputeFailure(technical) {
            var hint = "Core ML kunde inte köra modellen."
            if isLowMemory(physicalMemory) {
                hint += " Din Mac har \(gigabytes(physicalMemory)) GB minne, så stäng gärna andra program."
            }
            hint += " Försök igen, och hjälper inte det: ladda ned modellen igen."
            parts.append(hint)
        }
        parts.append("Teknisk information: \(technical)")
        return parts.joined(separator: "\n\n")
    }

    /// En rad till felloggen.
    public static func logEntry(
        date: Date,
        appVersion: String,
        model: String,
        step: FailureStep,
        physicalMemory: UInt64,
        technical: String
    ) -> String {
        let stamp = ISO8601DateFormatter().string(from: date)
        let oneLine = technical.replacingOccurrences(of: "\n", with: " ")
        return "\(stamp) | v\(appVersion) | \(model) | \(step.label) | \(gigabytes(physicalMemory)) GB | \(oneLine)"
    }

    /// Loggen får inte växa för alltid: de senaste raderna behålls.
    public static func trimmedLog(_ log: String, keeping lines: Int = 200) -> String {
        let all = log.split(separator: "\n", omittingEmptySubsequences: true)
        guard all.count > lines else { return log }
        return all.suffix(lines).joined(separator: "\n") + "\n"
    }
}
