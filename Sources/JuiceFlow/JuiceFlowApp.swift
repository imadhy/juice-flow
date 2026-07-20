import AppKit
import SwiftUI

@main
@MainActor
enum Main {
    static func main() {
        if CommandLine.arguments.contains("--dump") {
            dumpSnapshot()
        } else {
            JuiceFlowApp.main()
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
        """)
    }
}

struct JuiceFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var battery = BatteryService()

    var body: some Scene {
        WindowGroup("JuiceFlow") {
            ContentView()
                .environment(battery)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
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
        true
    }
}
