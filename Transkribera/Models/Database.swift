import Foundation
import SwiftData

// MARK: - Schemaversioner

/// Databasens första version, oförändrad sedan 0.1.0.
///
/// Ändrar du något i `Transcript` eller `TranscriptSegment` måste databasen få en ny
/// version, annars kan äldre användares data inte öppnas:
/// 1. Kopiera modellerna som de ser ut nu till `SchemaV1` (nästlade typer), så att den
///    gamla versionen finns kvar oförändrad.
/// 2. Lägg till `SchemaV2` med de nya modellerna och ett steg i `TranskriberaMigrationPlan`
///    (`.lightweight` för nya valfria fält eller fält med standardvärde, annars `.custom`).
/// CI:s uppgraderingstest (`scripts/upgrade-test.sh`) öppnar en databas från förra
/// versionen med den nya appen och stoppar releasen om något tappas.
enum SchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Transcript.self, TranscriptSegment.self]
    }
}

enum TranskriberaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

// MARK: - Öppna databasen

/// Öppnar databasen utan att någonsin krascha eller tyst slänga data.
///
/// - Första gången en ny version av appen startar kopieras databasen till
///   `Säkerhetskopior` innan den öppnas (och ev. migreras).
/// - Går databasen inte att öppna flyttas den till `Säkerhetskopior` och appen startar
///   med en tom databas. Användaren får veta det och var kopian ligger.
enum Database {
    static let storeName = "Transkribera.store"

    struct Result {
        let container: ModelContainer
        /// Visas för användaren vid start om något gick fel.
        let problem: String?
    }

    static var storeURL: URL { AppPaths.supportDirectory.appending(path: storeName) }

    static var backupsDirectory: URL {
        AppPaths.supportDirectory.appending(path: "Säkerhetskopior", directoryHint: .isDirectory)
    }

    static func open() -> Result {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let url = storeURL
        backUpIfNewVersion(url)

        do {
            return Result(container: try makeContainer(schema: schema, url: url), problem: nil)
        } catch {
            print("Kunde inte öppna databasen: \(error)")
        }

        let moved = moveAside(url, reason: "kunde-inte-oppnas")
        if let container = try? makeContainer(schema: schema, url: url) {
            let location = moved.map { " En kopia av den gamla databasen finns i \($0.path(percentEncoded: false))." } ?? ""
            return Result(
                container: container,
                problem: "Dina tidigare transkriberingar kunde inte läsas in, så appen startade med en tom lista.\(location) Hör av dig så hjälper vi dig att få tillbaka dem."
            )
        }

        // Sista utvägen: en databas i minnet, så att appen åtminstone startar.
        let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, migrationPlan: TranskriberaMigrationPlan.self, configurations: memory)
        return Result(
            container: container,
            problem: "Databasen kunde inte öppnas. Det du gör nu sparas inte när appen avslutas."
        )
    }

    private static func makeContainer(schema: Schema, url: URL) throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            migrationPlan: TranskriberaMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, url: url)
        )
    }

    // MARK: Säkerhetskopior

    private static let lastBuildKey = "databaseBackedUpForBuild"
    private static let keptBackups = 5

    /// Kopierar databasen innan en ny version av appen öppnar den första gången.
    private static func backUpIfNewVersion(_ url: URL, defaults: UserDefaults = .standard) {
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        guard defaults.string(forKey: lastBuildKey) != build else { return }
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            guard copyStore(url, label: "fore-bygge-\(build)") != nil else { return }
        }
        defaults.set(build, forKey: lastBuildKey)
    }

    /// SQLite-databasen består av upp till tre filer (`.store`, `-wal`, `-shm`).
    private static func storeFiles(_ url: URL) -> [URL] {
        ["", "-wal", "-shm"]
            .map { URL(filePath: url.path(percentEncoded: false) + $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
    }

    @discardableResult
    private static func copyStore(_ url: URL, label: String) -> URL? {
        transferStore(url, label: label) { try FileManager.default.copyItem(at: $0, to: $1) }
    }

    private static func moveAside(_ url: URL, reason: String) -> URL? {
        transferStore(url, label: reason) { try FileManager.default.moveItem(at: $0, to: $1) }
    }

    private static func transferStore(_ url: URL, label: String, _ transfer: (URL, URL) throws -> Void) -> URL? {
        let files = storeFiles(url)
        guard !files.isEmpty else { return nil }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
        let folder = backupsDirectory.appending(path: "\(stamp)-\(label)", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for file in files {
                try transfer(file, folder.appending(path: file.lastPathComponent))
            }
            pruneBackups()
            return folder
        } catch {
            print("Kunde inte säkerhetskopiera databasen: \(error)")
            return nil
        }
    }

    /// Behåller de senaste kopiorna. Kopior av databaser som inte gick att öppna tas aldrig bort.
    private static func pruneBackups() {
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(at: backupsDirectory, includingPropertiesForKeys: nil) else { return }
        let automatic = folders
            .filter { $0.lastPathComponent.contains("fore-bygge-") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for folder in automatic.dropFirst(keptBackups) {
            try? fm.removeItem(at: folder)
        }
    }
}
