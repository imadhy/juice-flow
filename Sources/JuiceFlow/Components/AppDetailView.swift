import AppKit
import SwiftUI

/// Panneau détail permanent du dashboard : l'application sélectionnée dans le
/// classement, en direct — avec son coût en autonomie.
struct AppDetailPanel: View {
    @Environment(BatteryService.self) private var battery
    @Environment(ProcessService.self) private var processes
    let app: AppPower?

    var body: some View {
        Group {
            if let app {
                detail(app)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "cursorarrow.click.2")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("Sélectionnez une application")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .card()
    }

    private func detail(_ app: AppPower) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                iconView(app)
                    .frame(width: 38, height: 38)
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
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(valueColor(app))
                Text(processes.source == .precision ? "en ce moment" : "pts d'impact")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Sparkline(values: app.history, color: valueColor(app))
                    .frame(height: 42)
                Text("2 dernières minutes")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            autonomyCost(app)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
                GridRow {
                    Text("CPU").foregroundStyle(.secondary)
                    Text(cpuText(app.cpuPercent))
                }
                if app.gpuPercent > 0.5 {
                    GridRow {
                        Text("GPU").foregroundStyle(.secondary)
                        Text(cpuText(app.gpuPercent))
                    }
                }
                GridRow {
                    Text("Processus").foregroundStyle(.secondary)
                    Text("\(app.processCount)")
                }
            }
            .font(.caption)

            // La répartition n'apparaît que si elle apporte de l'info :
            // plusieurs membres, ou un membre unique au nom différent du
            // groupe (ex : la VM Virtualization sous limactl).
            if !app.topChildren.isEmpty,
               app.topChildren.count > 1 || app.topChildren.first?.name != app.name {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Répartition")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(app.topChildren, id: \.name) { child in
                        HStack {
                            Text(child.name)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 10)
                            Text(childMetricText(child.metric))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                    if app.processCount > app.topChildren.count {
                        Text("et \(app.processCount - app.topChildren.count) autres…")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

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

            Spacer(minLength: 0)

            if let running = NSRunningApplication(processIdentifier: app.id),
               running.activationPolicy == .regular,
               running.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                Divider()
                HStack {
                    Button(role: .destructive) {
                        running.terminate()
                    } label: {
                        Label("Quitter l'app", systemImage: "xmark.circle")
                    }
                    Text("équivaut à ⌘Q")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .animation(.default, value: app)
    }

    /// Le bloc signature : ce que cette app coûte en temps de batterie.
    /// Calculé sur les moyennes glissantes (drain 2 min, conso soutenue de
    /// l'app) : l'estimation ne saute pas au gré des pics instantanés.
    @ViewBuilder
    private func autonomyCost(_ app: AppPower) -> some View {
        let snap = battery.snapshot
        VStack(alignment: .leading, spacing: 4) {
            Text("Coût d'autonomie")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if let watts = app.sustainedWatts,
               let gain = battery.autonomyGainMinutes(freeingWatts: watts),
               let now = battery.estimatedAutonomyHours {
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(TimeFormat.gain(gain))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(.green)
                    Text("en quittant cette app")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("autonomie \(TimeFormat.hours(now)) → \(TimeFormat.hours(now + gain / 60))"
                     + (snap.isExternalConnected ? " · si vous étiez sur batterie" : ""))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else if processes.source == .estimation {
                Text("Activez le mode précision pour le coût en minutes.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Text("Impact négligeable sur l'autonomie.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.green.opacity(0.07))
        )
    }

    @ViewBuilder
    private func iconView(_ app: AppPower) -> some View {
        if let icon = app.icon {
            Image(nsImage: icon).resizable().scaledToFit()
        } else {
            let glyph = DaemonGlyph.forApp(app)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(glyph.color.opacity(0.16))
                .overlay {
                    Image(systemName: glyph.symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(glyph.color)
                }
        }
    }

    /// « 42 % d'un cœur » sous 100 %, « ≈ 2,8 cœurs » au-delà.
    private func cpuText(_ percent: Double) -> String {
        percent >= 100
            ? String(format: "≈ %.1f cœurs", percent / 100)
            : String(format: "%.0f %% d'un cœur", percent)
    }

    /// Métrique d'un sous-processus : mW/W en précision, % CPU en estimation.
    private func childMetricText(_ metric: Double) -> String {
        if processes.source == .precision {
            return metric < 1000
                ? String(format: "%.0f mW", metric)
                : String(format: "%.1f W", metric / 1000)
        }
        return String(format: "%.0f %% CPU", metric)
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
