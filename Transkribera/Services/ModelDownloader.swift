import Foundation

/// Laddar ner KB-Whisper-modellerna, som ligger som zip-filer i en GitHub Release
/// (se `.github/workflows/kb-whisper-models.yml`), och packar upp dem.
enum ModelDownloader {
    static let releaseBaseURL = URL(string: "https://github.com/nicklasnilsson-ux/transkriberingsappen/releases/download/kb-whisper-v1/")!

    enum DownloadError: LocalizedError {
        case httpStatus(Int)
        case unzipFailed

        var errorDescription: String? {
            switch self {
            case .httpStatus(let status):
                return "Kunde inte ladda ner modellen (HTTP \(status)). Försök igen senare."
            case .unzipFailed:
                return "Kunde inte packa upp den nedladdade modellen."
            }
        }
    }

    /// Laddar ner `asset` och packar upp det i `destination`. Zip-filen innehåller
    /// en mapp med samma namn som `destination`.
    static func download(
        asset: String,
        to destination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let url = releaseBaseURL.appending(path: asset)
        let zip = try await downloadFile(from: url, progress: progress)
        defer { try? FileManager.default.removeItem(at: zip) }

        let parent = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destination)
        try await unzip(zip, into: parent)
        guard FileManager.default.fileExists(atPath: destination.path) else {
            throw DownloadError.unzipFailed
        }
    }

    private static func downloadFile(
        from url: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        var observation: NSKeyValueObservation?
        defer { observation?.invalidate() }
        let task = Box<URLSessionDownloadTask>()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let downloadTask = URLSession.shared.downloadTask(with: url) { location, response, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        continuation.resume(throwing: DownloadError.httpStatus(http.statusCode))
                        return
                    }
                    guard let location else {
                        continuation.resume(throwing: URLError(.badServerResponse))
                        return
                    }
                    // Filen raderas när blocket returnerar, så flytta den direkt.
                    let kept = FileManager.default.temporaryDirectory
                        .appending(path: UUID().uuidString + ".zip")
                    do {
                        try FileManager.default.moveItem(at: location, to: kept)
                        continuation.resume(returning: kept)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
                observation = downloadTask.progress.observe(\.fractionCompleted) { p, _ in
                    progress(p.fractionCompleted)
                }
                task.value = downloadTask
                downloadTask.resume()
            }
        } onCancel: {
            task.value?.cancel()
        }
    }

    private static func unzip(_ zip: URL, into directory: URL) async throws {
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-x", "-k", zip.path, directory.path]
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw DownloadError.unzipFailed }
        }.value
    }

    private final class Box<T>: @unchecked Sendable {
        var value: T?
    }
}
