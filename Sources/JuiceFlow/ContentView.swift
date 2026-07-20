import SwiftUI

/// Dashboard principal : jauge héros, flux d'énergie, grille bento.
struct ContentView: View {
    @Environment(BatteryService.self) private var battery
    @Environment(ProcessService.self) private var processes
    @State private var showPrecisionSetup = false
    @State private var selectedAppID: pid_t?

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
                subtitle: "max théorique ~1000"
            )
        }
    }

    @ViewBuilder
    private var sourceBadge: some View {
        if processes.source == .precision {
            badgeLabel("précision", color: .teal)
        } else {
            badgeLabel("estimation", color: .orange)
            if case .unavailable = processes.powerMetrics.state {
                Button("passer en précision") { showPrecisionSetup = true }
                    .buttonStyle(.link)
                    .font(.caption2)
            } else if case .failed = processes.powerMetrics.state {
                badgeLabel("erreur powermetrics", color: .red)
                    .help("Le flux powermetrics s'est interrompu — repli automatique sur l'estimation.")
            }
        }
    }

    private func detailBinding(for id: pid_t) -> Binding<Bool> {
        Binding(
            get: { selectedAppID == id },
            set: { presented in selectedAppID = presented ? id : nil }
        )
    }

    private func badgeLabel(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.14)))
    }

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Impact énergétique")
                    .font(.headline)
                sourceBadge
                Spacer()
                Text("\(processes.trackedProcessCount) processus")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .help(processes.source == .precision
                ? "Mesure officielle powermetrics en watts réels : CPU (cœurs P/E), GPU et wakeups, processus système compris."
                : "Score estimé à partir du CPU (même échelle que le Moniteur d'activité : ~100 ≈ un cœur saturé). Activez la précision pour des watts réels, GPU et processus système compris.")
            .alert("Activer le mode précision", isPresented: $showPrecisionSetup) {
                Button("Activer") {
                    Task { await processes.powerMetrics.installAuthorizationAndStart() }
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("""
                JuiceFlow utilisera powermetrics, l'outil de mesure d'Apple, \
                pour un impact énergétique exact : cœurs P/E, GPU et processus \
                système (WindowServer…) compris.

                Une règle sudo limitée à powermetrics sera créée pour votre \
                utilisateur. Mot de passe administrateur demandé une seule fois.
                """)
            }

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
                let top = Array(processes.apps.prefix(12))
                let maxImpact = top.first?.energyImpact ?? 1
                VStack(spacing: 10) {
                    ForEach(top) { app in
                        AppEnergyRow(app: app, maxImpact: maxImpact)
                            .onTapGesture { selectedAppID = app.id }
                            .popover(
                                isPresented: detailBinding(for: app.id),
                                arrowEdge: .trailing
                            ) {
                                AppDetailView(appID: app.id)
                            }
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
