import Foundation
import TranskriberaCore

/// Fel som stoppat en transkribering sparas i en textfil, så att de finns kvar även när
/// felrutan hunnit bytas ut. Filen innehåller aldrig någon text ur inspelningen, bara
/// datum, version, modell, steg, minne och felets tekniska text.
enum ErrorLog {
    static var fileURL: URL {
        AppPaths.supportDirectory.appending(path: "Fellogg.txt")
    }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    static func append(model: String, step: FailureStep, technical: String) {
        let entry = FailureExplainer.logEntry(
            date: Date(),
            appVersion: appVersion,
            model: model,
            step: step,
            physicalMemory: ProcessInfo.processInfo.physicalMemory,
            technical: technical
        )
        let existing = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        let updated = FailureExplainer.trimmedLog(existing + entry + "\n")
        try? updated.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    /// Den senaste delen av loggen, för knappen "Kopiera felinformation".
    static func recentEntries(_ count: Int = 10) -> String {
        let text = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        return text.split(separator: "\n").suffix(count).joined(separator: "\n")
    }
}
