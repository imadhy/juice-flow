import AppKit
import SwiftUI

@main
@MainActor
enum Main {
    static func main() {
        if CommandLine.arguments.contains("--dump") {
            dumpSnapshot()
        } else if CommandLine.arguments.contains("--top") {
            dumpTopApps()
        } else if CommandLine.arguments.contains("--pm") {
            dumpPowerMetrics()
        } else {
            JuiceFlowApp.main()
        }
    }

    /// Mode diagnostic : `JuiceFlow --top` échantillonne 3 s et imprime le
    /// classement, à croiser avec `top -o cpu`.
    private static func dumpTopApps() {
        let interval = CommandLine.arguments.compactMap(Double.init).first ?? 3
        let first = ProcessSampler.snapshot()
        print("Échantillonnage sur \(interval) s (\(first.usage.count) processus)…")
        Thread.sleep(forTimeInterval: interval)
        let second = ProcessSampler.snapshot()
        dumpTopAppsTable(first: first, second: second)
    }

    /// Mode diagnostic : `JuiceFlow --pm` prend un échantillon powermetrics
    /// (nécessite la règle sudoers) et imprime le classement précis.
    private static func dumpPowerMetrics() {
        print("Échantillon powermetrics via sudo -n…")
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        proc.arguments = ["-n", "/usr/bin/powermetrics",
                          "--samplers", "tasks", "--show-process-energy", "--show-process-gpu",
                          "-i", "1000", "-n", "1", "--format", "plist"]
        let stdout = Pipe()
        let stderr = Pipe()
        proc.standardOutput = stdout
        proc.standardError = stderr
        do { try proc.run() } catch {
            print("Impossible de lancer sudo : \(error.localizedDescription)")
            exit(1)
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let errText = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            print("Échec (code \(proc.terminationStatus)) : \(errText)")
            print("Règle sudoers absente ? Cliquez « passer en précision » dans l'app.")
            exit(1)
        }

        var buffer = data
        var documents = PowerMetricsParser.splitStream(buffer: &buffer)
        if !buffer.isEmpty { documents.append(buffer) }
        let tasks = documents.flatMap { PowerMetricsParser.tasks(from: $0) }
        print("\(data.count) octets, \(documents.count) document(s), \(tasks.count) tâches")
        print("  IMPACT   CPU ms/s   GPU ms/s   PID    NOM")
        for task in tasks.sorted(by: { $0.energyImpact > $1.energyImpact }).prefix(15) {
            let impact = String(format: "%7.1f", task.energyImpact)
            let cpu = String(format: "%9.1f", task.cpuMsPerS)
            let gpu = String(format: "%9.1f", task.gpuMsPerS)
            let pid = String(format: "%6d", task.pid)
            print("  \(impact)  \(cpu)  \(gpu)  \(pid)   \(task.name)")
        }
    }

    /// Mode diagnostic : `JuiceFlow --top` échantillonne et imprime le
    /// classement estimation, à croiser avec `top -o cpu`.
    private static func dumpTopAppsTable(first: ProcessSampler.Snapshot, second: ProcessSampler.Snapshot) {
        var iconCache: [pid_t: NSImage] = [:]
        let apps = ProcessService.aggregate(from: first, to: second, iconCache: &iconCache)
        print("  IMPACT   % CPU   RÉVEILS/S  PROC  APPLICATION")
        for app in apps.prefix(12) {
            let impact = String(format: "%7.1f", app.energyImpact)
            let cpu = String(format: "%6.1f", app.cpuPercent)
            let wakeups = String(format: "%9.1f", app.wakeupsPerSec)
            let count = String(format: "%4d", app.processCount)
            print("  \(impact)  \(cpu)  \(wakeups)  \(count)  \(app.name)")
        }
    }

    /// Mode diagnostic : `JuiceFlow --dump` imprime la lecture IOKit brute,
    /// pratique pour croiser avec `pmset -g batt` et `ioreg -rn AppleSmartBattery`.
    private static func dumpSnapshot() {
        guard let s = BatteryReader.read() else {
            print("Aucune batterie détectée.")
            exit(1)
        }
        print("""
        Batterie        \(s.percentage) %
        État            \(s.state)
        Puissance       \(String(format: "%.2f", s.watts)) W (\(String(format: "%.3f", s.voltage)) V × \(String(format: "%.3f", s.amperage)) A)
        Cycles          \(s.cycleCount)
        Santé           \(String(format: "%.1f", s.healthPercent)) % (\(s.nominalCapacity) / \(s.designCapacity) mAh)
        Température     \(String(format: "%.1f", s.temperature)) °C
        Secteur         \(s.isExternalConnected ? "branché" : "débranché")
        Temps restant   \(s.timeRemainingMinutes.map { "\($0) min" } ?? "—")
        SMC batterie    \(s.watts) W (signé, convention charge > 0)
        SMC système     \(s.systemWatts.map { String(format: "%.2f W", $0) } ?? "indisponible")
        SMC chargeur    \(s.adapterWatts.map { String(format: "%.2f W", $0) } ?? "indisponible")
        Énergie rest.   \(String(format: "%.1f", s.remainingEnergyWh)) Wh (\(s.rawCurrentCapacity) mAh × \(String(format: "%.2f", s.voltage)) V)
        Autonomie est.  \(s.estimatedAutonomyHours.map { TimeFormat.hours($0) } ?? "—") (drain réf. \(s.referenceDrainWatts.map { String(format: "%.1f W", $0) } ?? "—"))
        """)
    }
}

struct JuiceFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var battery = BatteryService()
    @State private var processes = ProcessService()

    var body: some Scene {
        WindowGroup("JuiceFlow", id: "main") {
            ContentView()
                .environment(battery)
                .environment(processes)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarView()
                .environment(battery)
                .environment(processes)
        } label: {
            MenuBarLabel()
                .environment(battery)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Nécessaire quand le binaire est lancé hors bundle (swift run) :
        // sans cela l'app n'apparaît pas au premier plan.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // L'app vit dans la barre des menus : fermer la fenêtre ne quitte plus.
        false
    }
}
