import AppKit
import Observation

/// Consommation agrégée d'une application (ou d'un daemon système) :
/// tous ses processus regroupés sous le PID responsable.
struct AppPower: Identifiable {
    let id: pid_t
    var name: String
    var bundleID: String?
    var icon: NSImage?
    /// Score d'impact énergétique, même échelle que le Moniteur d'activité :
    /// ~100 ≈ un cœur saturé. Formule : % CPU + pénalité wakeups.
    var energyImpact: Double
    var cpuPercent: Double     // % d'un cœur (peut dépasser 100 en multithread)
    var wakeupsPerSec: Double
    var processCount: Int
}

extension AppPower: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.energyImpact == rhs.energyImpact
            && lhs.cpuPercent == rhs.cpuPercent && lhs.processCount == rhs.processCount
    }
}

@MainActor
@Observable
final class ProcessService {
    private(set) var apps: [AppPower] = []
    private(set) var trackedProcessCount = 0

    @ObservationIgnored private var previous: ProcessSampler.Snapshot?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var iconCache: [pid_t: NSImage] = [:]
    @ObservationIgnored private var smoothedImpacts: [pid_t: Double] = [:]

    init() {
        previous = ProcessSampler.snapshot()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                self?.refresh()
            }
        }
    }

    private func refresh() {
        let current = ProcessSampler.snapshot()
        if let previous {
            var list = Self.aggregate(from: previous, to: current, iconCache: &iconCache)
            // Moyenne glissante exponentielle : les scores glissent au lieu de
            // sauter, le classement arrête de frétiller à chaque échantillon.
            for index in list.indices {
                let id = list[index].id
                if let prior = smoothedImpacts[id] {
                    list[index].energyImpact = prior * 0.55 + list[index].energyImpact * 0.45
                }
                smoothedImpacts[id] = list[index].energyImpact
            }
            let alive = Set(list.map(\.id))
            smoothedImpacts = smoothedImpacts.filter { alive.contains($0.key) }
            apps = list.sorted { $0.energyImpact > $1.energyImpact }
            trackedProcessCount = current.usage.count
        }
        previous = current
    }

    /// Agrège les deltas d'énergie/CPU entre deux échantillons par application.
    /// Statique et réutilisée par le mode CLI `--top`.
    static func aggregate(
        from previous: ProcessSampler.Snapshot,
        to current: ProcessSampler.Snapshot,
        iconCache: inout [pid_t: NSImage]
    ) -> [AppPower] {
        let components = previous.instant.duration(to: current.instant).components
        let elapsed = max(Double(components.seconds) + Double(components.attoseconds) / 1e18, 0.1)

        struct Group {
            var cpuNS: UInt64 = 0
            var wakeups: UInt64 = 0
            var count = 0
        }
        var groups: [pid_t: Group] = [:]

        for (pid, now) in current.usage {
            // Processus apparu en cours de fenêtre : servira de base au tour suivant.
            guard let before = previous.usage[pid], now.cpuNS >= before.cpuNS else { continue }
            let rpid = ProcessSampler.responsiblePid(pid)
            var group = groups[rpid, default: Group()]
            group.cpuNS += now.cpuNS - before.cpuNS
            group.wakeups += now.idleWakeups >= before.idleWakeups
                ? now.idleWakeups - before.idleWakeups : 0
            group.count += 1
            groups[rpid] = group
        }

        return groups.compactMap { rpid, group in
            let cpuPercent = Double(group.cpuNS) / 1e9 / elapsed * 100
            let wakeupsPerSec = Double(group.wakeups) / elapsed
            // Approximation du « impact énergétique » du Moniteur d'activité.
            let impact = cpuPercent + 0.2 * wakeupsPerSec
            guard impact >= 0.1 else { return nil }  // bruit
            let identity = resolveIdentity(rpid, iconCache: &iconCache)
            return AppPower(
                id: rpid,
                name: identity.name,
                bundleID: identity.bundleID,
                icon: identity.icon,
                energyImpact: impact,
                cpuPercent: cpuPercent,
                wakeupsPerSec: wakeupsPerSec,
                processCount: group.count
            )
        }
        .sorted { $0.energyImpact > $1.energyImpact }
    }

    // MARK: - Identité des apps

    private static func resolveIdentity(
        _ pid: pid_t, iconCache: inout [pid_t: NSImage]
    ) -> (name: String, bundleID: String?, icon: NSImage?) {
        if let app = NSRunningApplication(processIdentifier: pid) {
            if iconCache[pid] == nil, let icon = app.icon {
                iconCache[pid] = icon
            }
            return (app.localizedName ?? ProcessSampler.name(of: pid) ?? "PID \(pid)",
                    app.bundleIdentifier, iconCache[pid])
        }
        let rawName = ProcessSampler.name(of: pid) ?? "PID \(pid)"
        return (Self.friendlyDaemonNames[rawName] ?? rawName, nil, nil)
    }

    /// Noms lisibles pour les daemons système les plus courants.
    private static let friendlyDaemonNames: [String: String] = [
        "WindowServer": "Affichage (WindowServer)",
        "kernel_task": "Noyau macOS",
        "launchd": "launchd (système)",
        "mds": "Spotlight (indexation)",
        "mds_stores": "Spotlight (indexation)",
        "mdworker_shared": "Spotlight (indexation)",
        "corespotlightd": "Spotlight",
        "bird": "iCloud Drive",
        "cloudd": "iCloud (synchronisation)",
        "backupd": "Time Machine",
        "coreaudiod": "Audio système",
        "logd": "Journaux système",
        "trustd": "Sécurité (trustd)",
        "mediaanalysisd": "Analyse média",
        "photoanalysisd": "Photos (analyse)",
        "bluetoothd": "Bluetooth",
        "airportd": "Wi-Fi",
    ]
}
