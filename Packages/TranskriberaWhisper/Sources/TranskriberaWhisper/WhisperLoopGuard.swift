import CoreML
import Foundation
import WhisperKit

/// Skydd mot att WhisperKit avkodar samma ljudbit om och om igen utan att komma vidare.
///
/// I 0.5.2 kunde en transkribering stå still på t.ex. 46 % medan datorn gick för fullt.
/// Två saker i WhisperKit 1.1.1 samverkar:
///
/// 1. Med en ordlista (`promptTokens`) står ledtråden före `<|startoftranscript|>`.
///    `TimestampRulesFilter` letar bara efter uppgiftstoken bland de tre första
///    tokens och hittar den därför inte, så reglerna för tidsstämplar slutar gälla.
///    Modellen får då skriva t.ex. `<|0.00|><|0.00|>`, eller tidsstämplar som går bakåt.
/// 2. Fönsterloopen flyttar fram till sista tidsstämpeln. Är den `<|0.00|>` står den
///    still, och samma fönster avkodas igen med samma resultat, i all evighet.
///
/// `install(on:)` rättar båda: tidsstämpelreglerna gäller även med ordlista, och varje
/// fönster flyttar fram minst en bit. Missat tal fångas sedan av luckkontrollen i appen.
public enum WhisperLoopGuard {
    /// Läggs in en gång efter att modellen har lästs in. Ofarligt att anropa flera gånger.
    public static func install(on kit: WhisperKit) {
        if !(kit.segmentSeeker is AdvancingSegmentSeeker) {
            kit.segmentSeeker = AdvancingSegmentSeeker(wrapping: kit.segmentSeeker)
        }
        guard let tokenizer = kit.tokenizer else { return }
        var filters = kit.textDecoder.logitsFilters ?? []
        if !filters.contains(where: { $0 is PromptTimestampRulesFilter }) {
            filters.append(PromptTimestampRulesFilter(specialTokens: tokenizer.specialTokens))
            kit.textDecoder.logitsFilters = filters
        }
    }
}

/// WhisperKits regler för tidsstämplar, men med rätt startpunkt när en ledtråd
/// (`<|startofprev|>` + ordlista) står först. Utan ledtråd gör den ingenting, eftersom
/// WhisperKits eget filter fungerar då.
public final class PromptTimestampRulesFilter: LogitsFiltering {
    let specialTokens: SpecialTokens

    public init(specialTokens: SpecialTokens) {
        self.specialTokens = specialTokens
    }

    public func filterLogits(_ logits: MLMultiArray, withTokens tokens: [Int]) -> MLMultiArray {
        guard let sampleBegin = Self.sampleBegin(in: tokens, specialTokens: specialTokens) else { return logits }
        return TimestampRulesFilter(
            specialTokens: specialTokens,
            sampleBegin: sampleBegin,
            maxInitialTimestampIndex: nil,
            isModelMultilingual: false
        ).filterLogits(logits, withTokens: tokens)
    }

    /// Var modellens egna tokens börjar: direkt efter `<|0.00|>` som avslutar inledningen
    /// `<|startoftranscript|>`, (språk, uppgift,) `<|0.00|>`. `nil` utan ledtråd eller utan
    /// tidsstämplar.
    static func sampleBegin(in tokens: [Int], specialTokens: SpecialTokens) -> Int? {
        guard tokens.first == specialTokens.startOfPreviousToken,
              let start = tokens.firstIndex(of: specialTokens.startOfTranscriptToken),
              let marker = tokens[start...].firstIndex(where: {
                  $0 == specialTokens.timeTokenBegin || $0 == specialTokens.noTimestampsToken
              }),
              tokens[marker] == specialTokens.timeTokenBegin
        else { return nil }
        return marker + 1
    }
}

/// WhisperKits egen `SegmentSeeker`, men varje fönster måste flytta fram: står fönsterloopen
/// still hoppar den över fönstret, och flyttar den knappt framåt flyttas den minst en sekund.
/// Det gör att varje del av ljudet avkodas ett begränsat antal gånger.
public final class AdvancingSegmentSeeker: SegmentSeeking, @unchecked Sendable {
    public static let minimumAdvanceSeconds = 1.0

    private let base: any SegmentSeeking
    private let lock = NSLock()
    private var _forcedAdvances = 0

    /// Hur många gånger fönsterloopen har behövt knuffas framåt.
    public var forcedAdvances: Int { lock.withLock { _forcedAdvances } }

    public init(wrapping base: any SegmentSeeking = SegmentSeeker()) {
        self.base = base
    }

    public func findSeekPointAndSegments(
        decodingResult: DecodingResult,
        options: DecodingOptions,
        allSegmentsCount: Int,
        currentSeek seek: Int,
        segmentSize: Int,
        sampleRate: Int,
        timeToken: Int,
        specialToken: Int,
        tokenizer: WhisperTokenizer
    ) -> (Int, [TranscriptionSegment]?) {
        let (newSeek, segments) = base.findSeekPointAndSegments(
            decodingResult: decodingResult,
            options: options,
            allSegmentsCount: allSegmentsCount,
            currentSeek: seek,
            segmentSize: segmentSize,
            sampleRate: sampleRate,
            timeToken: timeToken,
            specialToken: specialToken,
            tokenizer: tokenizer
        )
        let advanced = Self.advancedSeek(
            currentSeek: seek, proposedSeek: newSeek, segmentSize: segmentSize, sampleRate: sampleRate
        )
        if advanced != newSeek {
            lock.withLock { _forcedAdvances += 1 }
        }
        return (advanced, segments)
    }

    static func advancedSeek(currentSeek: Int, proposedSeek: Int, segmentSize: Int, sampleRate: Int) -> Int {
        if proposedSeek <= currentSeek {
            return currentSeek + max(1, segmentSize)
        }
        let minimum = currentSeek + min(max(1, segmentSize), Int(minimumAdvanceSeconds * Double(sampleRate)))
        return max(proposedSeek, minimum)
    }

    public func addWordTimestamps(
        segments: [TranscriptionSegment],
        alignmentWeights: MLMultiArray,
        tokenizer: WhisperTokenizer,
        seek: Int,
        segmentSize: Int,
        prependPunctuations: String,
        appendPunctuations: String,
        lastSpeechTimestamp: Float,
        options: DecodingOptions,
        timings: TranscriptionTimings
    ) throws -> [TranscriptionSegment]? {
        try base.addWordTimestamps(
            segments: segments,
            alignmentWeights: alignmentWeights,
            tokenizer: tokenizer,
            seek: seek,
            segmentSize: segmentSize,
            prependPunctuations: prependPunctuations,
            appendPunctuations: appendPunctuations,
            lastSpeechTimestamp: lastSpeechTimestamp,
            options: options,
            timings: timings
        )
    }
}
