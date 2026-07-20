import AppKit
import SwiftUI

/// Vue détail d'une application (popover au clic sur une ligne du classement).
/// Se met à jour en direct tant qu'elle est ouverte.
struct AppDetailView: View {
    @Environment(ProcessService.self) private var processes
    let appID: pid_t

    var body: some View {
        if let app = processes.apps.first(where: { $0.id == appID }) {
            detail(app)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle")
                    .font(.title2)
                    .foregroundStyle(.green)
                Text("Application terminée ou inactive")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
    }

    private func detail(_ app: AppPower) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                iconView(app)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(app.bundleID ?? "processus système · PID \(app.id)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(valueText(app))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(valueColor(app))
                Text(processes.source == .precision ? "en ce moment" : "pts d'impact")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Sparkline(values: app.history, color: valueColor(app))
                    .frame(height: 44)
                Text("2 dernières minutes")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("CPU").foregroundStyle(.secondary)
                    Text(String(format: "%.1f %% d'un cœur", app.cpuPercent))
                }
                GridRow {
                    Text("Processus").foregroundStyle(.secondary)
                    Text("\(app.processCount)")
                }
            }
            .font(.caption)

            if app.isRunaway || app.isBackgroundActive {
                VStack(alignment: .leading, spacing: 4) {
                    if app.isRunaway {
                        Label("Consommation en forte hausse", systemImage: "flame.fill")
                            .foregroundStyle(.red)
                    }
                    if app.isBackgroundActive {
                        Label("Consomme en arrière-plan", systemImage: "moon.fill")
                            .foregroundStyle(.indigo)
                    }
                }
                .font(.caption)
            }

            if let running = NSRunningApplication(processIdentifier: appID),
               running.activationPolicy == .regular,
               running.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                Divider()
                HStack {
                    Button(role: .destructive) {
                        running.terminate()
                    } label: {
                        Label("Quitter l'application", systemImage: "xmark.circle")
                    }
                    Text("équivaut à ⌘Q")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(16)
        .frame(width: 280)
        .animation(.default, value: app)
    }

    @ViewBuilder
    private func iconView(_ app: AppPower) -> some View {
        if let icon = app.icon {
            Image(nsImage: icon).resizable().scaledToFit()
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.quinary)
                .overlay {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(.secondary)
                }
        }
    }

    private func valueText(_ app: AppPower) -> String {
        if let watts = app.watts {
            return watts < 1
                ? String(format: "%.0f mW", watts * 1000)
                : String(format: "%.1f W", watts)
        }
        return String(format: app.energyImpact < 10 ? "%.1f" : "%.0f", app.energyImpact)
    }

    private func valueColor(_ app: AppPower) -> Color {
        if let watts = app.watts {
            if watts < 0.5 { .green } else if watts < 2.5 { .orange } else { .red }
        } else {
            if app.energyImpact < 10 { .green } else if app.energyImpact < 60 { .orange } else { .red }
        }
    }
}
