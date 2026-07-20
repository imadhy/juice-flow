import SwiftUI

/// Dashboard principal : jauge héros, flux d'énergie, grille bento.
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
                .padding(40)
            }
        }
        .frame(width: 420)
    }

    private func dashboard(_ snap: BatterySnapshot) -> some View {
        VStack(spacing: 14) {
            BatteryGauge(snapshot: snap)
                .padding(.top, 26)
                .padding(.bottom, 8)

            PowerFlowCard(snapshot: snap)

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
}
