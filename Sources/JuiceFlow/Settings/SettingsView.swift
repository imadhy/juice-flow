import ServiceManagement
import SwiftUI

/// Réglages (⌘,) : lancement à la connexion, alertes, mode précision,
/// mises à jour.
struct SettingsView: View {
    @Environment(ProcessService.self) private var processes
    @Environment(UpdateService.self) private var updates

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

            Section {
                LabeledContent("Version \(UpdateService.currentVersion)") {
                    updateStatus
                }
            } header: {
                Text("Mises à jour")
            } footer: {
                Text(UpdateService.isBundled
                     ? "Vérification quotidienne auprès des releases GitHub. À l'installation, l'ancienne version part à la corbeille et l'app se relance."
                     : "Mises à jour indisponibles hors bundle .app (lancement dev).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize()
    }

    @ViewBuilder
    private var updateStatus: some View {
        switch updates.phase {
        case .idle:
            Button("Rechercher…") { Task { await updates.check() } }
                .disabled(!UpdateService.isBundled)
        case .checking:
            Label("Vérification…", systemImage: "hourglass")
                .foregroundStyle(.secondary)
        case .upToDate:
            HStack(spacing: 10) {
                Label("À jour", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Button("Rechercher…") { Task { await updates.check() } }
            }
        case .available(let release):
            Button("Installer la \(release.version)…") { Task { await updates.install() } }
                .buttonStyle(.borderedProminent)
                .help(release.notes.isEmpty ? "Notes de version sur GitHub." : release.notes)
        case .installing:
            Label("Installation…", systemImage: "hourglass")
                .foregroundStyle(.secondary)
        case .failed(let message, let pageURL):
            HStack(spacing: 10) {
                Label("Échec", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(message)
                if let pageURL {
                    Button("Ouvrir la page des releases") { NSWorkspace.shared.open(pageURL) }
                }
            }
        }
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
