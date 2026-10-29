import Foundation
import UniformTypeIdentifiers

/// Platser på disk som appen använder (inuti sandlådans Application Support).
enum AppPaths {
    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ensure(base.appending(path: "Transkribera", directoryHint: .isDirectory))
    }

    /// Nedladdade Whisper- och SpeakerKit-modeller.
    static var modelsDirectory: URL {
        ensure(supportDirectory.appending(path: "Models", directoryHint: .isDirectory))
    }

    static var mediaDirectory: URL {
        ensure(supportDirectory.appending(path: "Media", directoryHint: .isDirectory))
    }

    /// Talaridentifierarens turer per transkribering, utan text (se `SpeakerDiagnostics`).
    static var speakerTurnsDirectory: URL {
        ensure(supportDirectory.appending(path: "Talarturer", directoryHint: .isDirectory))
    }

    static var recordingsDirectory: URL {
        ensure(FileManager.default.temporaryDirectory.appending(path: "Recordings", directoryHint: .isDirectory))
    }

    @discardableResult
    private static func ensure(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// Kopierar importerade mediefiler till appens egen mapp så att de går att
/// spela upp även senare (sandlådan ger bara tillfällig åtkomst till filer
/// som användaren släpper eller väljer).
enum MediaStore {
    /// Filtyper som kan släppas eller väljas.
    static let supportedTypes: [UTType] = [.audio, .movie, .mpeg4Movie, .quickTimeMovie, .mpeg4Audio, .mp3, .wav, .aiff]

    static func url(for fileName: String) -> URL {
        AppPaths.mediaDirectory.appending(path: fileName)
    }

    /// Kopierar filen och returnerar det nya filnamnet.
    static func importFile(at source: URL) throws -> String {
        let didAccess = source.startAccessingSecurityScopedResource()
        defer { if didAccess { source.stopAccessingSecurityScopedResource() } }

        let ext = source.pathExtension.isEmpty ? "m4a" : source.pathExtension.lowercased()
        let fileName = "\(UUID().uuidString).\(ext)"
        try FileManager.default.copyItem(at: source, to: url(for: fileName))
        return fileName
    }

    /// Flyttar en fil som appen själv skapat (t.ex. en inspelning).
    static func moveFile(at source: URL) throws -> String {
        let ext = source.pathExtension.isEmpty ? "m4a" : source.pathExtension.lowercased()
        let fileName = "\(UUID().uuidString).\(ext)"
        try FileManager.default.moveItem(at: source, to: url(for: fileName))
        return fileName
    }

    static func delete(fileName: String) {
        try? FileManager.default.removeItem(at: url(for: fileName))
    }

    static func isSupported(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return supportedTypes.contains { type.conforms(to: $0) }
    }
}
