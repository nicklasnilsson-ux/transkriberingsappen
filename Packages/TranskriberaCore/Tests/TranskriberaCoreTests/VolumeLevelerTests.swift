import XCTest
@testable import TranskriberaCore

final class VolumeLevelerTests: XCTestCase {
    let rate = 16_000.0

    /// Ton med given styrka (som "tal") eller svagt brus (som tystnad), i sekunder.
    func audio(_ parts: [(seconds: Double, amplitude: Float)]) -> [Float] {
        var samples: [Float] = []
        var generator = SystemRandomNumberGenerator()
        for part in parts {
            for index in 0..<Int(part.seconds * rate) {
                let noise = Float.random(in: -0.0005...0.0005, using: &generator)
                samples.append(part.amplitude * Float(sin(2 * Double.pi * 220 * Double(index) / rate)) + noise)
            }
        }
        return samples
    }

    func rms(_ samples: ArraySlice<Float>) -> Float {
        (samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count)).squareRoot()
    }

    func testQuietSpeechIsBoostedAndLoudSpeechKept() {
        // Stark röst, tystnad, svag röst, tystnad.
        let samples = audio([(2, 0.3), (2, 0), (2, 0.03), (2, 0)])
        let leveled = VolumeLeveler.level(samples, sampleRate: rate)
        let second = Int(rate)

        XCTAssertEqual(rms(leveled[(0 * second + 4000)..<(1 * second)]), rms(samples[(0 * second + 4000)..<(1 * second)]), accuracy: 0.001)
        let quiet = rms(leveled[(4 * second + 8000)..<(5 * second + 8000)])
        XCTAssertGreaterThan(quiet, 0.08)
        XCTAssertLessThan(quiet, 0.12)
    }

    func testSilenceIsNotBoosted() {
        let samples = audio([(2, 0.3), (3, 0), (2, 0.3)])
        let leveled = VolumeLeveler.level(samples, sampleRate: rate)
        let second = Int(rate)
        let pause = (3 * second)..<(4 * second)
        XCTAssertEqual(rms(leveled[pause]), rms(samples[pause]), accuracy: 0.0005)
    }

    func testBoostIsLimitedAndNeverClips() {
        let samples = audio([(2, 0.005), (2, 0), (2, 0.95)])
        let leveled = VolumeLeveler.level(samples, sampleRate: rate)
        XCTAssertLessThanOrEqual(leveled.map { abs($0) }.max() ?? 0, 1)
        let second = Int(rate)
        let boosted = rms(leveled[(second / 2)..<second]) / rms(samples[(second / 2)..<second])
        XCTAssertLessThanOrEqual(boosted, VolumeLeveler.maxGain + 0.01)
    }

    func testEmptyInput() {
        XCTAssertEqual(VolumeLeveler.level([], sampleRate: rate), [])
    }
}
