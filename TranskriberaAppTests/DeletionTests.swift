import SQLite3
import SwiftData
import XCTest
import TranskriberaCore
@testable import Transkribera

/// Raderar man en fil ska inget av texten gå att nå, varken i databasen, i dess loggfil eller i
/// säkerhetskopiorna. Texterna är påhittade.
@MainActor
final class DeletionTests: XCTestCase {
    private let marker = "HEMLIGT-INNEHALL-4711"
    private var folder: URL!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "DeletionTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Segment och sparade versioner följer med när transkriberingen raderas.
    func testDeletingATranscriptDeletesSegmentsAndVersions() throws {
        let schema = Schema(versionedSchema: SchemaV2.self)
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let context = container.mainContext
        let t = Transcript(title: "Prov", mediaFileName: "x.m4a", originalFileName: "x.m4a", isVideo: false, duration: 2, modelName: "M0")
        context.insert(t)
        let output = TranscriptionOutput(segments: [SegmentData(start: 0, end: 2, text: marker, speaker: "Talare 1", words: [])], language: "sv")
        t.status = .completed
        t.addNewVersion(output, previousModelName: "", in: context, now: Date(timeIntervalSince1970: 1_000))
        t.addNewVersion(output, previousModelName: "M0", in: context, now: Date(timeIntervalSince1970: 2_000))
        XCTAssertFalse(try context.fetch(FetchDescriptor<TranscriptSegment>()).isEmpty)

        context.delete(t)
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<Transcript>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TranscriptSegment>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TranscriptVersion>()).count, 0)
    }

    /// Alla säkerhetskopior försvinner, även de som flyttats undan.
    func testEraseBackupsRemovesEveryCopy() throws {
        let backups = folder.appending(path: "Säkerhetskopior", directoryHint: .isDirectory)
        for name in ["2026-11-01-fore-bygge-70", "2026-11-02-kunde-inte-oppnas"] {
            let dir = backups.appending(path: name, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(marker.utf8).write(to: dir.appending(path: "Transkribera.store"))
        }
        Database.eraseBackups(in: backups)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: backups.path(percentEncoded: false)).count, 0)
    }

    /// Raderad text ligger inte kvar som byte i databasfilen eller dess loggfil efter `compact`.
    func testCompactLeavesNoDeletedTextInTheFiles() throws {
        let url = folder.appending(path: "Transkribera.store")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path(percentEncoded: false), &db), SQLITE_OK)
        func run(_ sql: String) { XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK, sql) }
        run("PRAGMA journal_mode = WAL;")
        run("CREATE TABLE t (id INTEGER PRIMARY KEY, text TEXT);")
        run("INSERT INTO t (text) VALUES ('\(marker)'), ('behalls');")
        run("DELETE FROM t WHERE text = '\(marker)';")
        XCTAssertTrue(Database.compact(storeAt: url))
        sqlite3_close(db)

        for suffix in ["", "-wal"] {
            let file = URL(filePath: url.path(percentEncoded: false) + suffix)
            guard let data = try? Data(contentsOf: file) else { continue }
            XCTAssertNil(data.range(of: Data(marker.utf8)), "Texten ligger kvar i \(file.lastPathComponent)")
        }
        // Det som inte raderades finns kvar.
        var check: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path(percentEncoded: false), &check), SQLITE_OK)
        var statement: OpaquePointer?
        sqlite3_prepare_v2(check, "SELECT count(*) FROM t;", -1, &statement, nil)
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        XCTAssertEqual(sqlite3_column_int(statement, 0), 1)
        sqlite3_finalize(statement)
        sqlite3_close(check)
    }
}
