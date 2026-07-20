import SwiftUI

/// Dashboard principal : jauge héros, flux d'énergie, grille bento.
struct ContentView: View {
    @Environment(BatteryService.self) private var battery
    @Environment(ProcessService.self) private var processes

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
                .padding(40)
            }
        }
    }

    private func dashboard(_ snap: BatterySnapshot) -> some View {
        HStack(alignment: .top, spacing: 14) {
            // Colonne gauche : tout l'état batterie.
            VStack(spacing: 14) {
                BatteryGauge(snapshot: snap)
                    .padding(.top, 22)
                PowerFlowCard(snapshot: snap)
                bentoGrid(snap)
            }
            .frame(width: 300)

            // Colonne droite : le classement des apps, pleine hauteur.
            appsSection
                .frame(width: 340)
                .padding(.top, 16)
        }
        // Hauteur figée : le contenu vit à l'intérieur, la fenêtre ne
        // « respire » plus à chaque rafraîchissement.
        .frame(height: 600, alignment: .top)
        .padding(20)
        .background(alignment: .top) {
            LinearGradient(
                colors: [snap.levelColor.opacity(0.16), .clear],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 280)
            .ignoresSafeArea()
        }
        .animation(.spring(duration: 0.5), value: snap)
    }

    private func bentoGrid(_ snap: BatterySnapshot) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())],
            spacing: 12
        ) {
            MetricCard(
                icon: "heart.fill", iconColor: .pink,
                title: "Santé",
                value: String(format: "%.0f %%", snap.healthPercent),
                subtitle: "\(snap.nominalCapacity) / \(snap.designCapacity) mAh"
            )
            MetricCard(
                icon: "clock", iconColor: .purple,
                title: "Temps restant",
                value: snap.timeRemainingValue,
                subtitle: snap.timeRemainingCaption
            )
            MetricCard(
                icon: "thermometer.medium", iconColor: .orange,
                title: "Température",
                value: String(format: "%.1f °C", snap.temperature),
                subtitle: snap.temperature < 40 ? "normale" : "élevée"
            )
            MetricCard(
                icon: "arrow.triangle.2.circlepath", iconColor: .blue,
                title: "Cycles",
                value: "\(snap.cycleCount)",
                subtitle: "limite de conception ~1000"
            )
        }
    }

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Impact énergétique")
                    .font(.headline)
                Text("estimation")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.orange.opacity(0.14)))
                Spacer()
                Text("\(processes.trackedProcessCount) processus")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .help("Score estimé à partir du CPU et des réveils système (même échelle que le Moniteur d'activité : ~100 ≈ un cœur saturé). Le mode powermetrics apportera la mesure exacte.")

            if processes.apps.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Première mesure en cours…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
            } else {
                let top = Array(processes.apps.prefix(11))
                let maxImpact = top.first?.energyImpact ?? 1
                VStack(spacing: 10) {
                    ForEach(top) { app in
                        AppEnergyRow(app: app, maxImpact: maxImpact)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .card()
        .animation(.spring(duration: 0.5), value: processes.apps)
    }
}
