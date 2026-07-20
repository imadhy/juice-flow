import AppKit
import SwiftUI

/// Libellé affiché dans la barre des menus : icône batterie + l'info qui
/// compte selon le contexte — le drain moyen sur batterie, le % sinon.
struct MenuBarLabel: View {
    @Environment(BatteryService.self) private var battery

    var body: some View {
        let snap = battery.snapshot
        HStack(spacing: 3) {
            Image(systemName: snap.batterySymbol)
            Text(labelText(snap))
                .monospacedDigit()
        }
    }

    private func labelText(_ snap: BatterySnapshot) -> String {
        if snap.state == .discharging, let drain = battery.smoothedDrainWatts {
            return String(format: "%.1f W", drain)
        }
        return "\(snap.percentage) %"
    }
}

/// Popover de la barre des menus : l'essentiel en un clin d'œil —
/// jauge compacte, autonomie, top 5 des gourmandes, accès au dashboard.
struct MenuBarView: View {
    @Environment(BatteryService.self) private var battery
    @Environment(ProcessService.self) private var processes
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let snap = battery.snapshot
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                BatteryGauge(snapshot: snap, size: 62)
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline(snap))
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(subline(snap))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Les plus gourmandes")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if processes.apps.isEmpty {
                    Text("mesure en cours…")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(Array(processes.apps.prefix(5))) { app in
                        row(app)
                    }
                }
            }

            Divider()

            HStack {
                Button("Ouvrir JuiceFlow") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Quitter") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 300)
        .animation(.default, value: processes.apps)
    }

    private func row(_ app: AppPower) -> some View {
        HStack(spacing: 8) {
            Group {
                if let icon = app.icon {
                    Image(nsImage: icon).resizable().scaledToFit()
                } else {
                    let glyph = DaemonGlyph.forApp(app)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(glyph.color.opacity(0.16))
                        .overlay {
                            Image(systemName: glyph.symbol)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(glyph.color)
                        }
                }
            }
            .frame(width: 18, height: 18)

            Text(app.name)
                .font(.callout)
                .lineLimit(1)
            if app.isRunaway {
                Image(systemName: "flame.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
            if app.isBackgroundActive {
                Image(systemName: "moon.fill")
                    .font(.caption2)
                    .foregroundStyle(.indigo)
            }
            Spacer(minLength: 8)
            Text(app.displayValue)
                .font(.callout.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(app.displayColor)
                .contentTransition(.numericText())
        }
    }

    private func headline(_ snap: BatterySnapshot) -> String {
        switch snap.state {
        case .discharging:
            battery.estimatedAutonomyHours.map { "\(TimeFormat.hours($0)) restantes" } ?? "Sur batterie"
        case .charging:
            snap.timeRemainingMinutes.map { "\(TimeFormat.hours(Double($0) / 60)) → 100 %" } ?? "En charge"
        case .full:
            "Batterie pleine"
        case .pluggedNotCharging:
            "Charge en pause"
        }
    }

    private func subline(_ snap: BatterySnapshot) -> String {
        let drain = battery.smoothedDrainWatts.map { String(format: "%.1f W", $0) } ?? "…"
        switch snap.state {
        case .discharging:
            return "\(snap.percentage) % · drain moyen \(drain)"
        case .charging, .full, .pluggedNotCharging:
            let autonomy = battery.estimatedAutonomyHours
                .map { "≈ \(TimeFormat.hours($0)) si débranché" } ?? "conso \(drain)"
            return "\(snap.percentage) % · \(autonomy)"
        }
    }
}
