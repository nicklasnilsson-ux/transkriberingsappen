import Foundation
import SpeakerKit
import TranskriberaCore
import XCTest
@testable import TranskriberaSpeakers

/// Kör talaridentifieringen på riktigt, på ett påhittat samtal från macOS talsyntes med
/// två olika röster. Felet vi letar efter: korta svar direkt efter en fråga ("Varje dag.")
/// hamnade hos den som frågade, med samma fel oavsett taligenkänningsmodell.
final class CommunityDiarizerTests: XCTestCase {
    func testShortRepliesGetTheirOwnSpeaker() async throws {
        let dialogue = try Dialogue.make()
        let diarizer = CommunityDiarizer(modelsDirectory: Self.modelsDirectory.appending(path: "community"))
        let turns = try await diarizer.turns(samples: dialogue.samples, speakers: .automatic)
        XCTAssertGreaterThanOrEqual(Set(turns.map(\.speaker)).count, 2, "Hittade bara en talare: \(turns)")

        let labels = dialogue.assign(turns)
        print("community-1:", dialogue.report(labels))
        let (interviewer, customer) = dialogue.roles(labels)
        XCTAssertNotEqual(interviewer, customer, "Intervjuaren och kunden fick samma talare")
        for (line, label) in zip(dialogue.lines, labels) {
            XCTAssertEqual(label, line.isInterviewer ? interviewer : customer, "Fel talare för \"\(line.text)\"")
        }
    }

    /// Utan omräkningen av korta turer hamnade "Varje dag." hos intervjuaren (CI 2026-10-29).
    /// Skriver bara ut resultatet, för jämförelse i loggen.
    func testCompareWithoutReembedding() async throws {
        let dialogue = try Dialogue.make()
        let diarizer = CommunityDiarizer(modelsDirectory: Self.modelsDirectory.appending(path: "community"))
        let turns = try await diarizer.turns(
            samples: dialogue.samples,
            config: CommunityDiarizer.config(for: .automatic, reembedShortTurns: false)
        )
        print("community-1 utan omräkning:", dialogue.report(dialogue.assign(turns)))
    }

    func testExactCountIsRespected() async throws {
        let dialogue = try Dialogue.make()
        let diarizer = CommunityDiarizer(modelsDirectory: Self.modelsDirectory.appending(path: "community"))
        let turns = try await diarizer.turns(samples: dialogue.samples, speakers: .exactly(2))
        XCTAssertEqual(Set(turns.map(\.speaker)).count, 2)
    }

    /// Samma samtal med dagens talaridentifiering (SpeakerKit 1.1.1). Testet skriver bara ut
    /// resultatet, för att kunna jämföra den gamla och den nya i CI-loggen.
    func testCompareWithSpeakerKit() async throws {
        let dialogue = try Dialogue.make()
        let kit = try await SpeakerKit(PyannoteConfig(
            downloadBase: Self.modelsDirectory.appending(path: "speakerkit").path,
            verbose: false,
            logLevel: .error
        ))
        let result = try await kit.diarize(audioArray: dialogue.samples, options: PyannoteDiarizationOptions())
        let turns = result.segments.compactMap { segment -> SpeakerTurn? in
            guard let id = segment.speaker.speakerId else { return nil }
            return SpeakerTurn(start: Double(segment.startTime), end: Double(segment.endTime), speaker: id)
        }
        print("SpeakerKit:", dialogue.report(dialogue.assign(turns)))
    }

    func testSpeakerNumbersFollowFirstAppearance() {
        let turns = CommunityDiarizer.turns(from: [
            (id: "S2", start: 0, end: 1), (id: "S1", start: 1, end: 2),
            (id: "S2", start: 2, end: 3), (id: "S3", start: 3, end: 3)
        ])
        XCTAssertEqual(turns.map(\.speaker), [0, 1, 0])
    }

    func testSpeakerCountReachesTheClustering() {
        let automatic = CommunityDiarizer.config(for: .automatic).clustering
        XCTAssertEqual(automatic.minSpeakers, 2)
        XCTAssertNil(automatic.maxSpeakers)
        XCTAssertNil(automatic.numSpeakers)

        let range = CommunityDiarizer.config(for: SpeakerCount(minimum: 2, maximum: 4)).clustering
        XCTAssertEqual(range.minSpeakers, 2)
        XCTAssertEqual(range.maxSpeakers, 4)

        XCTAssertEqual(CommunityDiarizer.config(for: .exactly(3)).clustering.numSpeakers, 3)
        XCTAssertTrue(CommunityDiarizer.config(for: .automatic).zeroVoteReembed.enabled)
    }

    static let modelsDirectory = FileManager.default.temporaryDirectory
        .appending(path: "TranskriberaSpeakersTests", directoryHint: .isDirectory)
}

/// Ett påhittat intervjusamtal: intervjuaren talar med en röst, kunden med en annan, och
/// svaren kommer direkt efter frågan med bara en kort paus, som i ett videosamtal.
struct Dialogue {
    struct Line {
        var text: String
        var isInterviewer: Bool
        var start: Double
        var end: Double
    }

    static let sampleRate = 16_000.0
    static let interviewerVoice = "Daniel"
    static let customerVoice = "Alva"

    static let script: [(String, Bool)] = [
        ("Hur ofta loggar ni in i systemet när ni jobbar med bokföringen?", true),
        ("Varje dag.", false),
        ("Och använder ni de färdiga rapporterna som finns där i dag?", true),
        ("Nej, det gör vi inte.", false),
        ("Berätta gärna lite om hur en vanlig vecka ser ut för dig.", true),
        ("Vi har ungefär tjugo kunder, och jag sköter det mesta av fakturorna själv på kvällarna när det är lugnt.", false),
        ("Vad skulle du tycka om att få förslag från en assistent?", true),
        ("Ja, det är ju jättebra.", false),
        ("Skulle du lita på förslagen?", true),
        ("Jag skulle lita på assistenten, absolut.", false),
        ("Då vill jag tacka så mycket för att du tog dig tid i dag.", true)
    ]

    var lines: [Line]
    var samples: [Float]

    static func make() throws -> Dialogue {
        let directory = CommunityDiarizerTests.modelsDirectory.appending(path: "dialogue")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pause = [Float](repeating: 0, count: Int(0.15 * sampleRate))
        var samples: [Float] = []
        var lines: [Line] = []
        for (index, (text, isInterviewer)) in script.enumerated() {
            let speech = try speak(text, voice: isInterviewer ? interviewerVoice : customerVoice,
                                   file: directory.appending(path: "line\(index).wav"))
            let start = Double(samples.count) / sampleRate
            samples += speech
            lines.append(Line(text: text, isInterviewer: isInterviewer, start: start, end: Double(samples.count) / sampleRate))
            samples += pause
        }
        return Dialogue(lines: lines, samples: samples)
    }

    /// Kopplar turerna till repliker på samma sätt som appen: ord för ord. Orden är jämnt
    /// utspridda över repliken, eftersom talsyntesen inte ger några ordtider.
    func assign(_ turns: [SpeakerTurn]) -> [String?] {
        let segments = lines.map { line -> SegmentData in
            let words = line.text.split(separator: " ").map(String.init)
            let step = (line.end - line.start) / Double(words.count)
            let timings = words.enumerated().map { index, word in
                WordTimingData(
                    word: " " + word,
                    start: line.start + Double(index) * step,
                    end: line.start + Double(index + 1) * step,
                    probability: 1
                )
            }
            return SegmentData(start: line.start, end: line.end, text: line.text, words: timings)
        }
        let assigned = SpeakerAssignment.assign(segments, turns: turns)
        // En replik som delats får den talare som har flest ord i den.
        return lines.map { line in
            let parts = assigned.filter { $0.start >= line.start - 0.01 && $0.end <= line.end + 0.01 }
            var counts: [String: Int] = [:]
            for part in parts { counts[part.speaker ?? "?", default: 0] += part.words.count }
            return counts.max { $0.value < $1.value }?.key
        }
    }

    /// Intervjuarens och kundens talare: den som har flest av respektive rolls långa repliker.
    /// Korta repliker räknas inte, eftersom det är dem testet kontrollerar.
    func roles(_ labels: [String?]) -> (interviewer: String?, customer: String?) {
        func majority(interviewer: Bool) -> String? {
            var counts: [String: Int] = [:]
            for (line, label) in zip(lines, labels)
            where line.isInterviewer == interviewer && line.text.split(separator: " ").count >= 6 {
                counts[label ?? "-", default: 0] += 1
            }
            return counts.max { $0.value < $1.value }?.key
        }
        return (majority(interviewer: true), majority(interviewer: false))
    }

    func report(_ labels: [String?]) -> String {
        let (interviewer, customer) = roles(labels)
        let correct = zip(lines, labels).filter { line, label in
            label == (line.isInterviewer ? interviewer : customer) && interviewer != customer
        }.count
        let details = zip(lines, labels).map { "\($1 ?? "-"): \($0.text)" }.joined(separator: " | ")
        return "\(correct) av \(lines.count) repliker rätt (intervjuare \(interviewer ?? "-"), kund \(customer ?? "-")). \(details)"
    }

    static func speak(_ text: String, voice: String, file: URL) throws -> [Float] {
        try? FileManager.default.removeItem(at: file)
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-v", voice, "--file-format=WAVE", "--data-format=LEI16@16000", "-o", file.path, text]
        try say.run()
        say.waitUntilExit()
        guard say.terminationStatus == 0 else {
            throw NSError(domain: "Dialogue", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "say misslyckades med rösten \(voice). Finns den på datorn?"
            ])
        }
        return try pcm16(from: Data(contentsOf: file))
    }

    /// 16-bitars PCM ur en WAV-fil, oavsett vilka andra delar filen har.
    static func pcm16(from data: Data) throws -> [Float] {
        let bytes = [UInt8](data)
        func uint32(_ offset: Int) -> Int {
            Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 | Int(bytes[offset + 2]) << 16 | Int(bytes[offset + 3]) << 24
        }
        var offset = 12
        while offset + 8 <= bytes.count {
            let id = String(decoding: bytes[offset..<(offset + 4)], as: UTF8.self)
            let size = uint32(offset + 4)
            if id == "data" {
                let end = min(bytes.count, offset + 8 + size)
                var samples: [Float] = []
                samples.reserveCapacity((end - offset - 8) / 2)
                var index = offset + 8
                while index + 1 < end {
                    let value = Int16(bitPattern: UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8)
                    samples.append(Float(value) / 32_768)
                    index += 2
                }
                return samples
            }
            offset += 8 + size + (size % 2)
        }
        throw NSError(domain: "Dialogue", code: 2, userInfo: [NSLocalizedDescriptionKey: "Ingen ljuddata i WAV-filen"])
    }
}
