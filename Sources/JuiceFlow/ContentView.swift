import SwiftUI

/// Dashboard principal.
/// Bandeau héros : jauge (autonomie au centre), flux d'énergie, stats.
/// Dessous : classement des apps + panneau détail permanent (master-detail).
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

    /// L'app affichée dans le panneau : la sélection, sinon la plus gourmande.
    private var selectedApp: AppPower? {
        processes.apps.first { $0.id == selectedAppID } ?? processes.apps.first
    }

    private func dashboard(_ snap: BatterySnapshot) -> some View {
        VStack(spacing: 14) {
            headerRow(snap)

            HStack(alignment: .top, spacing: 14) {
                appsSection
                    .frame(maxWidth: .infinity)
                AppDetailPanel(app: selectedApp)
                    .frame(width: 320)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(width: 880, height: 640, alignment: .top)
        .padding(20)
        .animation(.spring(duration: 0.5), value: snap)
    }

    // MARK: - Bandeau héros

    private func headerRow(_ snap: BatterySnapshot) -> some View {
        HStack(spacing: 14) {
            BatteryGauge(snapshot: snap, size: 150, heroText: gaugeHero(snap))
                .padding(.top, 10)
                .frame(width: 170)

            VStack(spacing: 8) {
                PowerFlowCard(snapshot: snap)
                if let context = headerContext(snap) {
                    // Branché, c'est LA réponse à « et si je débranche ? » :
                    // elle mérite mieux qu'une légende.
                    Label(context, systemImage: "hourglass")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 8) {
                StatChip(icon: "heart.fill", color: .pink,
                         value: String(format: "%.0f %%", snap.healthPercent),
                         label: "Santé · \(snap.nominalCapacity) mAh")
                StatChip(icon: "thermometer.medium", color: .orange,
                         value: String(format: "%.1f °C", snap.temperature),
                         label: snap.temperature < 40 ? "Température normale" : "Température élevée")
                StatChip(icon: "arrow.triangle.2.circlepath", color: .blue,
                         value: "\(snap.cycleCount)",
                         label: "Cycles · max ~1000")
            }
            .frame(width: 190)
        }
        .frame(height: 168)
    }

    /// Sur batterie, le héros de la jauge est le temps restant — la vraie
    /// réponse à « où j'en suis ? ». Sinon le pourcentage reprend la main.
    private func gaugeHero(_ snap: BatterySnapshot) -> String? {
        guard snap.state == .discharging,
              let autonomy = snap.estimatedAutonomyHours else { return nil }
        return TimeFormat.hours(autonomy)
    }

    private func headerContext(_ snap: BatterySnapshot) -> String? {
        switch snap.state {
        case .charging:
            guard let minutes = snap.timeRemainingMinutes else { return "calcul du temps de charge…" }
            return "chargée dans \(TimeFormat.hours(Double(minutes) / 60))"
        case .full, .pluggedNotCharging:
            guard let autonomy = snap.estimatedAutonomyHours else { return nil }
            return "≈ \(TimeFormat.hours(autonomy)) d'autonomie si débranché maintenant"
        case .discharging:
            guard let minutes = snap.timeRemainingMinutes else { return nil }
            return "estimation macOS : \(TimeFormat.hours(Double(minutes) / 60))"
        }
    }

    // MARK: - Classement

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
                let top = Array(processes.apps.prefix(9))
                let maxImpact = top.first?.energyImpact ?? 1
                VStack(spacing: 8) {
                    ForEach(top) { app in
                        AppEnergyRow(app: app, maxImpact: maxImpact,
                                     isSelected: app.id == selectedApp?.id)
                            .onTapGesture { selectedAppID = app.id }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .card()
        .animation(.spring(duration: 0.5), value: processes.apps)
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

    private func badgeLabel(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.14)))
    }
}
