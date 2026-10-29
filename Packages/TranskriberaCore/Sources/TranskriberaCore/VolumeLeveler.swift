import Foundation

/// Jämnar ut volymen så att en svag röst (t.ex. någon längre från mikrofonen) hörs lika
/// tydligt för modellen som en stark.
///
/// Ljudet mäts i korta block. Block med tal förstärks mot en målnivå, som mest
/// `maxGain` gånger; starka block och tystnad lämnas som de är, så att bruset i pauser
/// inte förstärks. Förstärkningen glider mellan blocken så att det inte klickar.
public enum VolumeLeveler {
    static let blockSeconds = 0.4
    /// Ungefär −20 dBFS, en normal talnivå.
    static let targetRMS: Float = 0.1
    /// Som mest 20 dB förstärkning.
    static let maxGain: Float = 10

    public static func level(_ samples: [Float], sampleRate: Double) -> [Float] {
        let blockSize = max(1, Int(blockSeconds * sampleRate))
        let blockCount = (samples.count + blockSize - 1) / blockSize
        guard blockCount > 0 else { return samples }

        var levels: [Float] = []
        levels.reserveCapacity(blockCount)
        for block in 0..<blockCount {
            let range = (block * blockSize)..<min(samples.count, (block + 1) * blockSize)
            var sum: Float = 0
            for index in range { sum += samples[index] * samples[index] }
            levels.append((sum / Float(range.count)).squareRoot())
        }

        // Tal är block som ligger tydligt över bruset (samma tanke som i SpeechCoverage).
        let sorted = levels.sorted()
        let floor = sorted[sorted.count / 10]
        let speechThreshold = max(floor * 4, 0.003)
        let gains = levels.map { level -> Float in
            guard level >= speechThreshold else { return 1 }
            return min(maxGain, max(1, targetRMS / level))
        }

        // Förstärkningen interpoleras linjärt mellan blockens mitt.
        var output = samples
        for index in samples.indices {
            let position = (Double(index) + 0.5) / Double(blockSize) - 0.5
            let lower = min(blockCount - 1, max(0, Int(position.rounded(.down))))
            let upper = min(blockCount - 1, lower + 1)
            let fraction = Float(min(1, max(0, position - Double(lower))))
            let gain = gains[lower] + (gains[upper] - gains[lower]) * fraction
            output[index] = min(1, max(-1, samples[index] * gain))
        }
        return output
    }
}
