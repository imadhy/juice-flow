import SwiftUI

/// Étape 1 : affichage brut mais propre des données batterie en temps réel.
/// L'identité visuelle (jauge, cartes, dégradés) arrive à l'étape 2.
struct ContentView: View {
    @Environment(BatteryService.self) private var battery

    var body: some View {
        Group {
            if battery.hasBattery {
                dashboard(battery.snapshot)
            } else {
                ContentUnavailableView(
                    "Aucune batterie détectée",
                    systemImage: "battery.slash",
                    description: Text("JuiceFlow nécessite un Mac portable.")
                )
            }
        }
        .frame(width: 380)
        .padding(28)
    }

    private func dashboard(_ snap: BatterySnapshot) -> some View {
        VStack(spacing: 24) {
            header(snap)
            Divider()
            metrics(snap)
        }
    }

    private func header(_ snap: BatterySnapshot) -> some View {
        VStack(spacing: 8) {
            Image(systemName: batterySymbol(snap))
                .font(.system(size: 44))
                .foregroundStyle(stateColor(snap))
                .symbolRenderingMode(.hierarchical)

            Text("\(snap.percentage) %")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())

            Text(stateLabel(snap))
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .animation(.default, value: snap.percentage)
    }

    private func metrics(_ snap: BatterySnapshot) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
            row("bolt.fill", "Batterie", wattsLabel(snap), valueColor: stateColor(snap))
            if let system = snap.systemWatts {
                row("laptopcomputer", "Conso. système", String(format: "%.1f W", system))
            }
            if snap.isExternalConnected, let adapter = snap.adapterWatts {
                row("powerplug.fill", "Chargeur", String(format: "%.1f W", adapter))
            }
            row("thermometer.medium", "Température",
                String(format: "%.1f °C", snap.temperature))
            row("arrow.triangle.2.circlepath", "Cycles", "\(snap.cycleCount)")
            row("heart.fill", "Santé",
                String(format: "%.0f %% (%d / %d mAh)", snap.healthPercent,
                       snap.nominalCapacity, snap.designCapacity))
            row("clock", "Temps restant", timeRemainingLabel(snap))
        }
    }

    private func row(_ symbol: String, _ label: String, _ value: String,
                     valueColor: Color = .primary) -> some View {
        GridRow {
            Label(label, systemImage: symbol)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.medium)
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .contentTransition(.numericText())
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .animation(.default, value: value)
    }

    // MARK: - Formatage

    private func stateLabel(_ snap: BatterySnapshot) -> String {
        switch snap.state {
        case .charging: "En charge"
        case .discharging: "Sur batterie"
        case .full: "Branché · batterie pleine"
        case .pluggedNotCharging: "Branché · charge en pause"
        }
    }

    private func stateColor(_ snap: BatterySnapshot) -> Color {
        switch snap.state {
        case .charging, .full: .green
        case .pluggedNotCharging: .blue
        case .discharging: snap.percentage <= 20 ? .red : .orange
        }
    }

    private func wattsLabel(_ snap: BatterySnapshot) -> String {
        if abs(snap.watts) < 0.05 { return "0 W" }
        return String(format: "%+.1f W", snap.watts)
    }

    private func timeRemainingLabel(_ snap: BatterySnapshot) -> String {
        guard let minutes = snap.timeRemainingMinutes else {
            return snap.state == .full ? "∞" : "calcul en cours…"
        }
        let suffix = snap.state == .charging ? " avant 100 %" : ""
        return "\(minutes / 60) h \(String(format: "%02d", minutes % 60))\(suffix)"
    }

    private func batterySymbol(_ snap: BatterySnapshot) -> String {
        if snap.state == .charging { return "battery.100percent.bolt" }
        let levels = [0, 25, 50, 75, 100]
        let nearest = levels.min { abs($0 - snap.percentage) < abs($1 - snap.percentage) } ?? 100
        return "battery.\(nearest)percent"
    }
}
