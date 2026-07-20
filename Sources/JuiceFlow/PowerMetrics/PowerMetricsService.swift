import AppKit
import Observation

/// Mode précision : streame `sudo -n powermetrics --samplers tasks` (plist)
/// pour obtenir l'impact énergétique officiel d'Apple par processus — GPU et
/// processus système compris.
///
/// L'autorisation repose sur une règle sudoers dédiée, limitée à powermetrics
/// pour l'utilisateur courant, installée par l'app via le dialogue
/// d'administration natif (`installAuthorization`). Sans règle, le service
/// reste `unavailable` et l'app fonctionne en mode estimation.
///
/// Nettoyage : à la fermeture de l'app le flux reçoit SIGTERM (relayé par
/// sudo) ; en cas de crash, powermetrics meurt de SIGPIPE à la fermeture du
/// tube. Pas de processus root orphelin.
@MainActor
@Observable
final class PowerMetricsService {
    enum State: Equatable {
        case probing        // vérification de l'autorisation en cours
        case unavailable    // pas de règle sudoers : mode estimation
        case running
        case failed(String)
    }

    private(set) var state: State = .probing
    private(set) var tasks: [PMTask] = []

    @ObservationIgnored private var lastSample: ContinuousClock.Instant?
    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var buffer = Data()
    /// 3 s quand une vue est visible, 30 s sinon — le flux ne s'arrête
    /// jamais : l'historique par app s'écrit 24 h/24 pour presque rien.
    @ObservationIgnored private var intervalSeconds = 3

    /// Vrai si des données précises fraîches sont disponibles (fenêtre de
    /// fraîcheur proportionnelle à la cadence courante).
    var isFresh: Bool {
        guard state == .running, let lastSample else { return false }
        return lastSample.duration(to: .now) < .seconds(intervalSeconds * 3 + 5)
    }

    /// Change la cadence d'échantillonnage (redémarre le flux si actif).
    func setCadence(seconds: Int) {
        guard intervalSeconds != seconds else { return }
        intervalSeconds = seconds
        if process != nil {
            stop()
            start()
        }
    }

    init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in
            // Fermeture propre du flux root avec l'app.
            MainActor.assumeIsolated { PowerMetricsShutdown.terminate() }
        }
        Task { await probeAndStart() }
    }

    func probeAndStart() async {
        state = .probing
        let probe = try? await Self.run("/usr/bin/sudo", ["-n", "-l", "/usr/bin/powermetrics"])
        guard probe?.status == 0 else {
            state = .unavailable
            return
        }
        start()
    }

    /// Setup guidé : installe la règle sudoers via le dialogue admin natif,
    /// puis démarre le flux. Retourne false si l'utilisateur annule ou si
    /// la validation visudo échoue.
    @discardableResult
    func installAuthorizationAndStart() async -> Bool {
        let user = NSUserName()
        let rule = "\(user) ALL=(root) NOPASSWD: /usr/bin/powermetrics"
        let file = "/etc/sudoers.d/juiceflow-powermetrics"
        let shell = "echo '\(rule)' > \(file) && /bin/chmod 440 \(file)"
            + " && /usr/sbin/visudo -cf \(file) || { /bin/rm -f \(file); exit 1; }"
        let script = "do shell script \"\(shell)\" with administrator privileges"

        guard let result = try? await Self.run("/usr/bin/osascript", ["-e", script]),
              result.status == 0 else {
            state = .unavailable
            return false
        }
        await probeAndStart()
        return state == .running
    }

    /// Supprime la règle sudoers (dialogue admin) et repasse en estimation.
    func removeAuthorization() async {
        let script = "do shell script \"/bin/rm -f /etc/sudoers.d/juiceflow-powermetrics\" with administrator privileges"
        guard let result = try? await Self.run("/usr/bin/osascript", ["-e", script]),
              result.status == 0 else { return }
        stop()
        state = .unavailable
    }

    // MARK: - Flux powermetrics

    private func start() {
        stop()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        proc.arguments = [
            "-n", "/usr/bin/powermetrics",
            "--samplers", "tasks",
            "--show-process-energy",  // sans ce flag, pas de clé energy_impact
            "--show-process-gpu",
            "-i", "\(intervalSeconds * 1000)",
            "--format", "plist",
        ]
        let stdout = Pipe()
        proc.standardOutput = stdout
        proc.standardError = FileHandle.nullDevice

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor [weak self] in self?.ingest(data) }
        }
        proc.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            Task { @MainActor [weak self] in self?.streamDied(status: status) }
        }

        do {
            try proc.run()
            process = proc
            PowerMetricsShutdown.register(pid: proc.processIdentifier)
            state = .running
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func stop() {
        process?.terminate()
        process = nil
        buffer.removeAll()
    }

    /// Relance le flux s'il est tombé. La sonde sudo (~50 ms) est assez
    /// rapide pour être systématique.
    func resumeIfAuthorized() async {
        guard process == nil else { return }
        await probeAndStart()
    }

    private func ingest(_ data: Data) {
        buffer.append(data)
        // Garde-fou si le format ne contient jamais de séparateur NUL.
        if buffer.count > 20_000_000 { buffer.removeAll() }

        // Seul le document le plus récent compte, et son parsing (~300 Ko de
        // plist) n'a rien à faire sur le thread principal.
        guard let latest = PowerMetricsParser.splitStream(buffer: &buffer).last else { return }
        Task.detached(priority: .utility) { [weak self] in
            let parsed = PowerMetricsParser.tasks(from: latest)
            guard !parsed.isEmpty else { return }
            await MainActor.run {
                guard let self else { return }
                self.tasks = parsed
                self.lastSample = .now
                if self.state != .running { self.state = .running }
            }
        }
    }

    private func streamDied(status: Int32) {
        guard process != nil else { return }  // arrêt volontaire déjà géré
        process = nil
        state = status == 0 ? .unavailable : .failed("powermetrics interrompu (code \(status))")
    }

    // MARK: - Utilitaires

    /// Exécute un binaire et attend sa fin (hors acteur principal).
    nonisolated static func run(
        _ path: String, _ arguments: [String]
    ) async throws -> (status: Int32, output: String) {
        try await withCheckedThrowingContinuation { continuation in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: path)
            proc.arguments = arguments
            let out = Pipe()
            proc.standardOutput = out
            proc.standardError = out
            proc.terminationHandler = { finished in
                let data = out.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: (finished.terminationStatus,
                                                String(decoding: data, as: UTF8.self)))
            }
            do { try proc.run() } catch { continuation.resume(throwing: error) }
        }
    }
}

/// Registre minimal pour tuer le flux sudo/powermetrics à la fermeture,
/// y compris depuis le contexte non isolé de willTerminate.
@MainActor
enum PowerMetricsShutdown {
    private static var streamPid: pid_t?

    static func register(pid: pid_t) { streamPid = pid }

    static func terminate() {
        if let pid = streamPid { kill(pid, SIGTERM) }
        streamPid = nil
    }
}
