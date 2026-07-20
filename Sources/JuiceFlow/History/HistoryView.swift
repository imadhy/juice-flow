import AppKit
import Charts
import SwiftUI

/// Onglet Historique : courbe de batterie 24 h, résumé du jour,
/// top des consommateurs du jour.
struct HistoryView: View {
    @Environment(HistoryService.self) private var history
    @Environment(ProcessService.self) private var processes

    @State private var curve: [CurvePoint] = []
    @State private var topApps: [AppDayTotal] = []
    @State private var summary = DaySummary(minutesOnBattery: 0, energyWh: 0)
    @State private var energyDelta: Double?
    @State private var iconCache: [String: NSImage] = [:]
    @State private var refreshTask: Task<Void, Never>?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 12) {
                summaryChips
                curveCard
            }
            .frame(maxWidth: .infinity)

            topAppsCard
                .frame(width: 320)
        }
        .onAppear {
            reload()
            refreshTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(60), tolerance: .seconds(5))
                    reload()
                }
            }
        }
        .onDisappear { refreshTask?.cancel() }
    }

    private func reload() {
        curve = history.curve(hoursBack: 24)
        topApps = history.topAppsToday(limit: 8)
        summary = history.daySummary()
        energyDelta = history.energyDeltaVersusYesterday()
    }

    // MARK: - Résumé du jour

    private var summaryChips: some View {
        HStack(spacing: 12) {
            StatChip(icon: "battery.100percent", color: .green,
                     value: TimeFormat.hours(Double(summary.minutesOnBattery) / 60),
                     label: "sur batterie aujourd'hui")
            StatChip(icon: "bolt.fill", color: .yellow,
                     value: String(format: "%.1f Wh", summary.energyWh),
                     label: energyDelta.map {
                         String(format: "consommés · %+.0f %% vs hier", $0)
                     } ?? "consommés aujourd'hui")
        }
    }

    // MARK: - Courbe 24 h

    private var curveCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Niveau de batterie · 24 h")
                .font(.headline)

            if curve.count < 2 {
                emptyState("La courbe se dessinera au fil des minutes…")
            } else {
                Chart(curve) { point in
                    AreaMark(
                        x: .value("Heure", point.timestamp),
                        y: .value("Niveau", point.percentage)
                    )
                    // Un souffle, pas une dalle : à 100 % constant, une aire
                    // dense remplirait tout le graphe.
                    .foregroundStyle(
                        LinearGradient(colors: [.green.opacity(0.10), .clear],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    LineMark(
                        x: .value("Heure", point.timestamp),
                        y: .value("Niveau", point.percentage)
                    )
                    .foregroundStyle(.green)
                    .lineStyle(StrokeStyle(lineWidth: 1.8))
                }
                .chartYScale(domain: 0...100)
                // Axe honnête : les vraies dernières 24 h, même si les
                // données n'en couvrent qu'un segment (il grandira).
                .chartXScale(domain: Date.now.addingTimeInterval(-24 * 3600)...Date.now)
                .chartYAxis {
                    AxisMarks(values: [0, 25, 50, 75, 100])
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 4)) {
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour())
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card()
    }

    // MARK: - Top du jour

    private var topAppsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top du jour")
                .font(.headline)

            if processes.source == .estimation && topApps.isEmpty {
                emptyState("Activez le mode précision pour suivre l'énergie par application.")
            } else if topApps.isEmpty {
                emptyState("Les totaux du jour apparaîtront d'ici quelques minutes.")
            } else {
                let maxEnergy = topApps.first?.energyMWh ?? 1
                VStack(spacing: 10) {
                    ForEach(topApps) { app in
                        row(app, maxEnergy: maxEnergy)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .card()
    }

    private func row(_ app: AppDayTotal, maxEnergy: Double) -> some View {
        HStack(spacing: 8) {
            iconView(app)
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(app.name)
                        .font(.callout)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(energyText(app.energyMWh))
                        .font(.callout.weight(.semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                Capsule()
                    .fill(.quinary)
                    .frame(height: 4)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Color.green.gradient)
                            .frame(width: max(240 * app.energyMWh / max(maxEnergy, 0.001), 4))
                    }
            }
        }
        .frame(height: 36)
    }

    @ViewBuilder
    private func iconView(_ app: AppDayTotal) -> some View {
        if let icon = icon(for: app) {
            Image(nsImage: icon).resizable().scaledToFit()
        } else {
            let glyph = DaemonGlyph.forName(app.name)
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(glyph.color.opacity(0.16))
                .overlay {
                    Image(systemName: glyph.symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(glyph.color)
                }
        }
    }

    private func icon(for app: AppDayTotal) -> NSImage? {
        if let cached = iconCache[app.name] { return cached }
        guard let bundleID = app.bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        iconCache[app.name] = icon
        return icon
    }

    private func energyText(_ mwh: Double) -> String {
        mwh < 1000
            ? String(format: "%.0f mWh", mwh)
            : String(format: "%.2f Wh", mwh / 1000)
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 24)
    }
}
