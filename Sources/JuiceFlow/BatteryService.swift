import Foundation
import IOKit.ps
import Observation

/// Source de vérité observable pour l'UI. Rafraîchit la lecture IOKit :
/// - toutes les 3 s (les watts bougent en permanence) ;
/// - immédiatement quand le système signale un changement d'alimentation
///   (branchement/débranchement du secteur) via `IOPSNotificationCreateRunLoopSource`.
@MainActor
@Observable
final class BatteryService {
    private(set) var snapshot = BatterySnapshot()
    private(set) var hasBattery = true

    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var powerSource: CFRunLoopSource?

    init() {
        refresh()
        startPolling()
        registerForPowerChanges()
    }

    func refresh() {
        if let snap = BatteryReader.read() {
            snapshot = snap
            hasBattery = true
        } else {
            hasBattery = false
        }
    }

    private func startPolling() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                self?.refresh()
            }
        }
    }

    private func registerForPowerChanges() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let service = Unmanaged<BatteryService>.fromOpaque(context).takeUnretainedValue()
            // Le callback est délivré sur la run loop principale.
            MainActor.assumeIsolated { service.refresh() }
        }, context)?.takeRetainedValue() else { return }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        powerSource = source
    }
}
