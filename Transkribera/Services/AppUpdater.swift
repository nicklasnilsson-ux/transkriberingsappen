import Combine
import Foundation
import Sparkle

/// Automatiska uppdateringar via Sparkle. Flödet (appcast) och signaturerna byggs av
/// release-workflowen, se docs/RELEASE.md.
@MainActor
final class AppUpdater: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    @Published var automaticallyChecks: Bool {
        didSet { updater.automaticallyChecksForUpdates = automaticallyChecks }
    }
    @Published var automaticallyInstalls: Bool {
        didSet { updater.automaticallyDownloadsUpdates = automaticallyInstalls }
    }

    private let delegate: UpdaterDelegate
    private let controller: SPUStandardUpdaterController

    init() {
        let delegate = UpdaterDelegate()
        self.delegate = delegate
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: delegate, userDriverDelegate: nil)
        _automaticallyChecks = Published(initialValue: controller.updater.automaticallyChecksForUpdates)
        _automaticallyInstalls = Published(initialValue: controller.updater.automaticallyDownloadsUpdates)
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
    }

    private var updater: SPUUpdater { controller.updater }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    /// Versionen som körs, t.ex. "0.4.0 (4)".
    static var currentVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

/// Betakanalen: versioner märkta `beta` i appcasten visas bara för den som valt det.
private final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        UserDefaults.standard.bool(forKey: SettingsKey.betaUpdates) ? ["beta"] : []
    }
}
