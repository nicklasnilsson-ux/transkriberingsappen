import Foundation

/// Stegen i en transkribering, så att förloppet kan visa "Steg 2 av 4". Stapeln börjar
/// om i varje steg, och stegräkningen förklarar varför.
public enum TranscriptionStep: Equatable, Sendable {
    case model
    case audio
    case transcribe
    case gapCheck
    case speakers

    /// Stegen som körs, i ordning. Modellsteget finns bara när modellen måste laddas
    /// ner eller in, och luckkontrollen bara för Whisper-modellerna.
    public static func plan(needsModel: Bool, checksGaps: Bool, identifiesSpeakers: Bool) -> [TranscriptionStep] {
        var steps: [TranscriptionStep] = []
        if needsModel { steps.append(.model) }
        steps += [.audio, .transcribe]
        if checksGaps { steps.append(.gapCheck) }
        if identifiesSpeakers { steps.append(.speakers) }
        return steps
    }

    /// "Steg 2 av 4", eller `nil` om steget inte ingår eller det bara finns ett steg.
    public static func label(for step: TranscriptionStep, in plan: [TranscriptionStep]) -> String? {
        guard plan.count > 1, let index = plan.firstIndex(of: step) else { return nil }
        return "Steg \(index + 1) av \(plan.count)"
    }
}
