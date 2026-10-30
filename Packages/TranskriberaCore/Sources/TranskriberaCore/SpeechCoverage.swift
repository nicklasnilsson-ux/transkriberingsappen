import Foundation

/// Ett tidsintervall i sekunder.
public struct TimeRange: Hashable, Sendable {
    public var start: Double
    public var end: Double

    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }

    public var duration: Double { end - start }
}

/// Hittar tal i ljudet som transkriberingen hoppat över.
///
/// Whisper kan avsluta ett 30-sekundersfönster i förtid och hoppa vidare, så att hela
/// repliker saknas utan att något syns i texten. Här jämförs var det låter som tal
/// (ljudnivå) med var det finns text, och luckorna kan sedan transkriberas om.
public enum SpeechCoverage {
    static let frameSeconds = 0.03
    /// Pauser kortare än så här räknas som samma talstycke.
    static let mergeGap = 0.5
    /// Talstycken kortare än så här räknas inte (klick, harklingar).
    static let minimumSpeech = 0.3
    /// Så mycket marginal får segmentens tider ha.
    static let segmentSlack = 0.3
    /// Kortare luckor än så här lämnas, t.ex. "mm" som modellen med rätta hoppar över.
    public static let minimumGap = 2.0

    /// Tidsintervall där ljudet är tydligt starkare än bakgrunden.
    public static func speechRegions(in samples: [Float], sampleRate: Double) -> [TimeRange] {
        let frameLength = max(1, Int(frameSeconds * sampleRate))
        let frameCount = samples.count / frameLength
        guard frameCount > 0 else { return [] }

        var levels: [Float] = []
        levels.reserveCapacity(frameCount)
        for frame in 0..<frameCount {
            var sum: Float = 0
            for sample in samples[(frame * frameLength)..<((frame + 1) * frameLength)] { sum += sample * sample }
            levels.append((sum / Float(frameLength)).squareRoot())
        }

        // Bakgrunden är den tionde percentilen; tal ska vara klart starkare än den.
        let sorted = levels.sorted()
        let floor = sorted[sorted.count / 10]
        let threshold = max(floor * 4, 0.01)

        var regions: [TimeRange] = []
        var regionStart: Int?
        for (index, level) in levels.enumerated() {
            if level >= threshold {
                if regionStart == nil { regionStart = index }
            } else if let start = regionStart {
                regions.append(range(start, index, frameLength, sampleRate))
                regionStart = nil
            }
        }
        if let start = regionStart { regions.append(range(start, frameCount, frameLength, sampleRate)) }

        return merge(regions, within: mergeGap).filter { $0.duration >= minimumSpeech }
    }

    /// Delar av `speech` som inget segment täcker, minst `minimumGap` långa.
    public static func uncovered(speech: [TimeRange], segments: [SegmentData], minimumGap: Double = minimumGap) -> [TimeRange] {
        let covered = merge(
            segments.map { TimeRange(start: $0.start - segmentSlack, end: $0.end + segmentSlack) }
                .sorted { $0.start < $1.start },
            within: 0
        )
        var gaps: [TimeRange] = []
        for region in speech {
            var pieces = [region]
            for cover in covered where cover.end > region.start && cover.start < region.end {
                pieces = pieces.flatMap { piece -> [TimeRange] in
                    var rest: [TimeRange] = []
                    if cover.start > piece.start { rest.append(TimeRange(start: piece.start, end: min(piece.end, cover.start))) }
                    if cover.end < piece.end { rest.append(TimeRange(start: max(piece.start, cover.end), end: piece.end)) }
                    return rest.filter { $0.duration > 0 }
                }
            }
            gaps += pieces
        }
        return merge(gaps.sorted { $0.start < $1.start }, within: mergeGap).filter { $0.duration >= minimumGap }
    }

    /// Tal som `reference` (en annan taligenkännare) har text för men `segments` saknar,
    /// minst `minimumGap` långa. Ger säkrare luckor än ljudnivån, som också ger utslag på
    /// skratt och bakgrundsljud.
    public static func missing(from reference: [SegmentData], in segments: [SegmentData], minimumGap: Double = minimumGap) -> [TimeRange] {
        let speech = reference.map { TimeRange(start: $0.start, end: $0.end) }.filter { $0.duration > 0 }
        return uncovered(speech: speech, segments: segments, minimumGap: minimumGap)
    }

    /// Tal som finns i någon av listorna, hopslaget. Så läggs en andra taligenkännares
    /// tal till ljudnivåns, utan att ersätta det.
    public static func combine(_ first: [TimeRange], _ second: [TimeRange]) -> [TimeRange] {
        merge((first + second).sorted { $0.start < $1.start }, within: 0)
    }

    /// Lägger till de ord ur `reference` som ligger i en lucka, för luckor som ännu saknar
    /// text efter omkörningen. Per ord, så att en lucka som bara täcker en del av en lång
    /// mening inte tar med resten av den (och inte missar den om meningen är lång).
    public static func fill(_ segments: [SegmentData], with reference: [SegmentData], gaps: [TimeRange]) -> [SegmentData] {
        func inGap(_ start: Double, _ end: Double) -> Bool {
            let middle = (start + end) / 2
            return gaps.contains { (($0.start)...($0.end)).contains(middle) }
        }
        var found: [SegmentData] = []
        for segment in reference {
            guard !segment.words.isEmpty else {
                if inGap(segment.start, segment.end) { found.append(segment) }
                continue
            }
            // Följder av ord i luckan blir varsitt segment.
            var run: [WordTimingData] = []
            func flush() {
                guard let first = run.first, let last = run.last else { return }
                let text = run.map { $0.word.trimmed }.joined(separator: " ")
                found.append(SegmentData(start: first.start, end: last.end, text: text, words: run))
                run = []
            }
            for word in segment.words {
                if inGap(word.start, word.end) { run.append(word) } else { flush() }
            }
            flush()
        }
        return (segments + found).sorted { $0.start < $1.start }
    }

    static func merge(_ ranges: [TimeRange], within gap: Double) -> [TimeRange] {
        var merged: [TimeRange] = []
        for range in ranges {
            if let last = merged.last, range.start - last.end <= gap {
                merged[merged.count - 1].end = max(last.end, range.end)
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    private static func range(_ start: Int, _ end: Int, _ frameLength: Int, _ sampleRate: Double) -> TimeRange {
        TimeRange(start: Double(start * frameLength) / sampleRate, end: Double(end * frameLength) / sampleRate)
    }
}

public extension SegmentData {
    /// Samma segment flyttat `offset` sekunder, t.ex. när en del av ljudet transkriberats för sig.
    func shifted(by offset: Double) -> SegmentData {
        SegmentData(
            start: start + offset,
            end: end + offset,
            text: text,
            speaker: speaker,
            words: words.map { WordTimingData(word: $0.word, start: $0.start + offset, end: $0.end + offset, probability: $0.probability) }
        )
    }
}
