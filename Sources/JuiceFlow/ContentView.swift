import SwiftUI

/// Dashboard principal.
/// Bandeau héros : jauge (autonomie au centre), flux d'énergie, stats.
/// Dessous : classement des apps + panneau détail permanent (master-detail).
struct ContentView: View {
    enum Tab { case live, history }

    @Environment(BatteryService.self) private var battery
    @Environment(ProcessService.self) private var processes
    @Environment(UpdateService.self) private var updates
    @State private var showPrecisionSetup = false
    @State private var selectedAppID: pid_t?
    @State private var tab: Tab = .live
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @State private var showOnboarding = false

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
        // Pilote la cadence de mesure et la présence dans le Dock :
        // fenêtre fermée → mode économie + app « accessoire » (barre des
        // menus uniquement, plus d'icône Dock ni de point blanc).
        //
        // La logique vit dans `syncViewers` (constat de visibilité réelle,
        // idempotent) : onAppear/onDisappear et les notifications NSWindow
        // ne sont que des accélérateurs — selon la version de macOS,
        // certains ne tirent jamais (SwiftUI garde la vue vivante après
        // fermeture). Le tick de sondage rattrape toujours.
        .onAppear {
            processes.syncViewers()
            updates.checkIfStale()
            if !hasOnboarded { showOnboarding = true }
        }
        .onDisappear { processes.syncViewers() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in
            processes.syncViewers()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            processes.syncViewers()
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView {
                hasOnboarded = true
                showOnboarding = false
            }
        }
    }

    /// L'app affichée dans le panneau : la sélection, sinon la plus gourmande.
    private var selectedApp: AppPower? {
        processes.apps.first { $0.id == selectedAppID } ?? processes.apps.first
    }

    /// Invisible tant qu'il n'y a rien : un badge en haut à droite quand une
    /// mise à jour attend, un sablier discret pendant son installation.
    @ViewBuilder
    private var updateBadge: some View {
        if case .available(let release) = updates.phase {
            Button {
                Task { await updates.install() }
            } label: {
                Label("Mise à jour \(release.version)", systemImage: "sparkles")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.teal)
            .help(release.notes.isEmpty
                  ? "Télécharge, installe et relance JuiceFlow."
                  : release.notes)
        } else if case .installing = updates.phase {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Mise à jour…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func dashboard(_ snap: BatterySnapshot) -> some View {
        VStack(spacing: 12) {
            ZStack {
                Picker("", selection: $tab) {
                    Text("Temps réel").tag(Tab.live)
                    Text("Historique").tag(Tab.history)
                }
                .pickerStyle(.segmented)
                .frame(width: 240)

                HStack {
                    Spacer()
                    updateBadge
                }
            }

            headerRow(snap)

            Group {
                if tab == .live {
                    HStack(alignment: .top, spacing: 14) {
                        appsSection
                            .frame(maxWidth: .infinity)
                        AppDetailPanel(app: selectedApp)
                            .frame(width: 320)
                    }
                } else {
                    HistoryView()
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(width: 880, height: 660, alignment: .top)
        .padding(20)
        // Pas d'animation d'arbre global : le snapshot change toutes les 3 s
        // (au centième de volt près) et forcerait tout le dashboard — halo,
        // ombres — à re-rendre 60 fps pendant 0,5 s. Chaque composant anime
        // localement ce qui le concerne.
    }

    // MARK: - Bandeau héros

    /// Une seule carte unifiée : jauge (niveau), titre temporel (la réponse
    /// à « combien de temps ? »), flux d'énergie, stats derrière un filet.
    private func headerRow(_ snap: BatterySnapshot) -> some View {
        HStack(spacing: 18) {
            BatteryGauge(snapshot: snap, size: 140)
                .animation(.spring(duration: 0.8), value: snap.percentage)

            VStack(alignment: .leading, spacing: 12) {
                headline(snap)
                    .animation(.default, value: snap)
                PowerFlowCard(snapshot: snap)
                    .animation(.default, value: snap)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .padding(.vertical, 6)

            statsColumn(snap)
                .animation(.default, value: snap)
                .frame(width: 165)
        }
        .padding(18)
        .card()
        .frame(height: 196)
    }

    private func statsColumn(_ snap: BatterySnapshot) -> some View {
        let score = SessionScore.compute(battery: battery, processes: processes)
        return VStack(alignment: .leading, spacing: 10) {
            StatChip(icon: "speedometer", color: score.color,
                     value: "\(score.value)",
                     label: "score de session",
                     showsBackground: false)
                .help(score.factors.isEmpty
                      ? "Session saine : rien à signaler."
                      : score.factors.joined(separator: "\n"))
            StatChip(icon: "heart.fill", color: .pink,
                     value: String(format: "%.0f %%", snap.healthPercent),
                     label: "Santé · \(snap.nominalCapacity) mAh",
                     showsBackground: false)
            StatChip(icon: "thermometer.medium", color: .orange,
                     value: String(format: "%.1f °C", snap.temperature),
                     label: snap.temperature < 40 ? "Température normale" : "Température élevée",
                     showsBackground: false)
            StatChip(icon: "arrow.triangle.2.circlepath", color: .blue,
                     value: "\(snap.cycleCount)",
                     label: "Cycles · max ~1000",
                     showsBackground: false)
        }
    }

    /// Le gros titre contextuel du bandeau : toujours une réponse en temps.
    private func headline(_ snap: BatterySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .lastTextBaseline, spacing: 7) {
                Text(headlineValue(snap))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(headlineLabel(snap))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Text(headlineSubtitle(snap))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .contentTransition(.numericText())
        }
    }

    private func headlineValue(_ snap: BatterySnapshot) -> String {
        switch snap.state {
        case .discharging:
            return battery.estimatedAutonomyHours.map { TimeFormat.hours($0) } ?? "…"
        case .charging:
            return snap.timeRemainingMinutes.map { TimeFormat.hours(Double($0) / 60) } ?? "En charge"
        case .full, .pluggedNotCharging:
            return battery.estimatedAutonomyHours.map { "≈ \(TimeFormat.hours($0))" } ?? "Branché"
        }
    }

    private func headlineLabel(_ snap: BatterySnapshot) -> String {
        switch snap.state {
        case .discharging: "d'autonomie restante"
        case .charging: snap.timeRemainingMinutes != nil ? "avant charge complète" : ""
        case .full, .pluggedNotCharging:
            battery.estimatedAutonomyHours != nil ? "d'autonomie si débranché" : ""
        }
    }

    private func headlineSubtitle(_ snap: BatterySnapshot) -> String {
        let drain = battery.smoothedDrainWatts.map { String(format: "%.1f W", $0) } ?? "…"
        switch snap.state {
        case .discharging:
            return "au rythme moyen des 2 dernières minutes · \(drain)"
        case .charging:
            let autonomy = battery.estimatedAutonomyHours
                .map { "≈ \(TimeFormat.hours($0)) d'autonomie si débranché" } ?? "calcul en cours"
            return "\(autonomy) · conso moyenne \(drain)"
        case .full:
            return "batterie pleine · consommation moyenne \(drain)"
        case .pluggedNotCharging:
            return "charge en pause · consommation moyenne \(drain)"
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
                let top = Array(processes.apps.prefix(8))
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
