import AppKit
import Observation

/// Consommation agrégée d'une application (ou d'un daemon système) :
/// tous ses processus regroupés sous le PID responsable.
struct AppPower: Identifiable {
    let id: pid_t
    var name: String
    var bundleID: String?
    var icon: NSImage?
    /// Métrique de classement. En estimation : score façon Moniteur
    /// d'activité (~100 ≈ un cœur saturé). En précision : milliwatts.
    var energyImpact: Double
    /// Puissance réelle en watts — uniquement en mode précision.
    var watts: Double?
    var cpuPercent: Double     // % d'un cœur (peut dépasser 100 en multithread)
    var wakeupsPerSec: Double
    var processCount: Int
}

extension AppPower: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.energyImpact == rhs.energyImpact
            && lhs.watts == rhs.watts && lhs.cpuPercent == rhs.cpuPercent
            && lhs.processCount == rhs.processCount
    }
}

@MainActor
@Observable
final class ProcessService {
    enum ImpactSource: Equatable {
        case estimation   // deltas CPU libproc, sans privilèges
        case precision    // powermetrics : mesure officielle Apple
    }

    private(set) var apps: [AppPower] = []
    private(set) var trackedProcessCount = 0
    private(set) var source: ImpactSource = .estimation
    let powerMetrics = PowerMetricsService()

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
        if powerMetrics.isFresh {
            publish(Self.fromPowerMetrics(powerMetrics.tasks, iconCache: &iconCache),
                    processCount: powerMetrics.tasks.count,
                    source: .precision)
            // L'échantillonnage estimation reste chaud pour un repli sans trou.
            previous = ProcessSampler.snapshot()
            return
        }

        let current = ProcessSampler.snapshot()
        if let previous {
            publish(Self.aggregate(from: previous, to: current, iconCache: &iconCache),
                    processCount: current.usage.count,
                    source: .estimation)
        }
        previous = current
    }

    /// Lissage EMA + tri + publication, commun aux deux sources.
    private func publish(_ freshList: [AppPower], processCount: Int, source: ImpactSource) {
        if source != self.source { smoothedImpacts.removeAll() }
        var list = freshList
        for index in list.indices {
            let id = list[index].id
            if let prior = smoothedImpacts[id] {
                list[index].energyImpact = prior * 0.55 + list[index].energyImpact * 0.45
            }
            smoothedImpacts[id] = list[index].energyImpact
        }
        let alive = Set(list.map(\.id))
        smoothedImpacts = smoothedImpacts.filter { alive.contains($0.key) }
        if source == .precision {
            // En précision, la métrique lissée est en milliwatts.
            for index in list.indices { list[index].watts = list[index].energyImpact / 1000 }
        }
        apps = list.sorted { $0.energyImpact > $1.energyImpact }
        trackedProcessCount = processCount
        self.source = source
    }

    /// Construit le classement depuis les tâches powermetrics, regroupées par
    /// application via le PID responsable (comme le mode estimation).
    static func fromPowerMetrics(
        _ pmTasks: [PMTask], iconCache: inout [pid_t: NSImage]
    ) -> [AppPower] {
        struct Group {
            var impact = 0.0
            var cpuMs = 0.0
            var count = 0
            var leaderName: String?
        }
        var groups: [pid_t: Group] = [:]

        for task in pmTasks {
            let rpid = task.pid > 0 ? ProcessSampler.responsiblePid(task.pid) : task.pid
            var group = groups[rpid, default: Group()]
            group.impact += task.energyImpact
            group.cpuMs += task.cpuMsPerS
            group.count += 1
            if rpid == task.pid { group.leaderName = task.name }
            groups[rpid] = group
        }

        return groups.compactMap { rpid, group in
            guard group.impact >= 5 else { return nil }  // < 5 mW : bruit
            var identity = resolveIdentity(rpid, iconCache: &iconCache)
            // powermetrics voit des processus que libproc ne peut pas nommer
            // sans privilèges (WindowServer, kernel…) : son nom fait foi.
            if identity.icon == nil, identity.name.hasPrefix("PID "), let leader = group.leaderName {
                identity.name = friendlyDaemonNames[leader] ?? leader
            }
            return AppPower(
                id: rpid,
                name: identity.name,
                bundleID: identity.bundleID,
                icon: identity.icon,
                energyImpact: group.impact,  // milliwatts
                watts: group.impact / 1000,
                cpuPercent: group.cpuMs / 10,  // ms par seconde → % d'un cœur
                wakeupsPerSec: 0,
                processCount: group.count
            )
        }
        .sorted { $0.energyImpact > $1.energyImpact }
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
