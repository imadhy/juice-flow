import ServiceManagement
import SwiftUI

/// Réglages (⌘,) : lancement à la connexion, alertes, mode précision.
struct SettingsView: View {
    @Environment(ProcessService.self) private var processes

    @AppStorage("alertsEnabled") private var alertsEnabled = true
    @AppStorage("alertSensitivity") private var sensitivityRaw = AlertSensitivity.normal.rawValue

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemError: String?

    var body: some View {
        Form {
            Section("Général") {
                Toggle("Lancer JuiceFlow à la connexion", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        updateLoginItem(enabled)
                    }
                if let loginItemError {
                    Text(loginItemError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Toggle("Alerter quand une app s'emballe sur batterie", isOn: $alertsEnabled)
                Picker("Sensibilité", selection: $sensitivityRaw) {
                    ForEach(AlertSensitivity.allCases) { sensitivity in
                        Text(sensitivity.label).tag(sensitivity.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!alertsEnabled)
            } header: {
                Text("Alertes")
            } footer: {
                Text("Les alertes ne se déclenchent que sur batterie, après une surconsommation soutenue. Chaque app est ensuite silencieuse 30 minutes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Mesure") {
                LabeledContent("Impact énergétique") {
                    measureStatus
                }
                if processes.powerMetrics.state == .running {
                    Button("Retirer l'autorisation powermetrics…", role: .destructive) {
                        Task { await processes.powerMetrics.removeAuthorization() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize()
    }

    @ViewBuilder
    private var measureStatus: some View {
        switch processes.powerMetrics.state {
        case .running:
            Label("Précision active (powermetrics)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.teal)
        case .unavailable:
            Button("Activer le mode précision…") {
                Task { await processes.powerMetrics.installAuthorizationAndStart() }
            }
        case .probing:
            Label("Vérification…", systemImage: "hourglass")
                .foregroundStyle(.secondary)
        case .failed:
            Label("Erreur — repli sur l'estimation", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    private func updateLoginItem(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
        } catch {
            loginItemError = "Impossible de modifier le réglage : \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
