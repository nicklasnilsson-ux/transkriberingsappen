import SwiftUI

struct UpdateSettingsView: View {
    @EnvironmentObject private var updater: AppUpdater
    @AppStorage(SettingsKey.betaUpdates) private var betaUpdates = false

    var body: some View {
        Form {
            Section {
                Toggle("Sök efter uppdateringar automatiskt", isOn: $updater.automaticallyChecks)
                Toggle("Ladda ner och installera automatiskt", isOn: $updater.automaticallyInstalls)
                    .disabled(!updater.automaticallyChecks)
            } footer: {
                Text("Transkribera kollar en gång om dagen om det finns en ny version. Nya versioner laddas ner i bakgrunden och installeras när du avslutar appen.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Få betaversioner", isOn: $betaUpdates)
            } header: {
                Text("Betaversioner")
            } footer: {
                Text("Testa nya funktioner innan de släpps till alla. Betor kan innehålla fel. Stänger du av får du nästa stabila version när den kommer.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Installerad version", value: AppUpdater.currentVersion)
                Button("Sök efter uppdateringar nu") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
                    .help("Kolla direkt om det finns en nyare version")
            }
        }
        .formStyle(.grouped)
    }
}
