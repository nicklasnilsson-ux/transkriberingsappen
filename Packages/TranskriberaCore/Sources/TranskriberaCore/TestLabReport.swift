import Foundation

/// Det som loggas för varje körning i Testlabbet. Innehåller ingen text, bara tider och
/// mått, så att loggen går att läsa utan att intervjun syns.
public struct TestLabReport: Codable, Sendable {
    /// Ett stycke som Whisper skrev, med hur säker modellen var. `temperature` över 0
    /// betyder att texten underkändes och skrevs om med mer slump.
    public struct WhisperSegment: Codable, Equatable, Sendable {
        public var start: Double
        public var end: Double
        public var words: Int
        public var temperature: Double
        public var averageLogProbability: Double
        public var compressionRatio: Double
        public var noSpeechProbability: Double

        public init(start: Double, end: Double, words: Int, temperature: Double,
                    averageLogProbability: Double, compressionRatio: Double, noSpeechProbability: Double) {
            self.start = start
            self.end = end
            self.words = words
            self.temperature = temperature
            self.averageLogProbability = averageLogProbability
            self.compressionRatio = compressionRatio
            self.noSpeechProbability = noSpeechProbability
        }
    }

    /// Luckor där det lät som tal men saknades text, och som kördes om.
    public struct Gaps: Codable, Equatable, Sendable {
        public var count: Int
        public var seconds: Double
        public var segmentsAdded: Int

        public init(count: Int, seconds: Double, segmentsAdded: Int) {
            self.count = count
            self.seconds = seconds
            self.segmentsAdded = segmentsAdded
        }
    }

    public struct Seconds: Codable, Equatable, Sendable {
        public var total: Double
        public var transcription: Double
        public var gapCheck: Double

        public init(total: Double, transcription: Double, gapCheck: Double) {
            self.total = total
            self.transcription = transcription
            self.gapCheck = gapCheck
        }
    }

    public var run: TestLabRun
    public var differences: [String]
    public var appVersion: String
    public var startedAt: Date
    public var seconds: Seconds?
    public var words: Int?
    public var segments: Int?
    public var gaps: Gaps?
    public var whisperSegments: [WhisperSegment]?
    /// Pianissimos egen säkerhet för hela texten (0–1).
    public var pianissimoConfidence: Double?
    public var error: String?

    public init(run: TestLabRun, appVersion: String, startedAt: Date) {
        self.run = run
        self.differences = run.differences
        self.appVersion = appVersion
        self.startedAt = startedAt
    }

    /// Antal Whisper-stycken som underkändes minst en gång och skrevs om med mer slump.
    public var rewrittenSegments: Int? {
        whisperSegments.map { $0.filter { $0.temperature > 0 }.count }
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    // MARK: - Sammanfattning

    public static let summaryHeader = "körning;beskrivning;ändring;sekunder totalt;sekunder transkribering;sekunder luckkontroll;ord;stycken;omskrivna stycken;luckor;luckor sekunder;pianissimo säkerhet;fel"

    /// En rad i sammanfattningen (semikolon, så att Numbers och Excel på svenska öppnar den rätt).
    public var summaryLine: String {
        func number(_ value: Double?, decimals: Int = 1) -> String {
            guard let value else { return "" }
            return String(format: "%.\(decimals)f", value).replacingOccurrences(of: ".", with: ",")
        }
        func clean(_ text: String) -> String {
            text.replacingOccurrences(of: ";", with: ",").replacingOccurrences(of: "\n", with: " ")
        }
        let fields: [String] = [
            run.id,
            clean(run.title),
            clean(differences.isEmpty ? "ingen" : differences.joined(separator: ", ")),
            number(seconds?.total),
            number(seconds?.transcription),
            number(seconds?.gapCheck),
            words.map(String.init) ?? "",
            segments.map(String.init) ?? "",
            rewrittenSegments.map(String.init) ?? "",
            gaps.map { String($0.count) } ?? "",
            number(gaps?.seconds),
            number(pianissimoConfidence, decimals: 3),
            clean(error ?? "")
        ]
        return fields.joined(separator: ";")
    }
}
