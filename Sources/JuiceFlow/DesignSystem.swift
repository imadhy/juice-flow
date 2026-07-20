import SwiftUI

// MARK: - Langage visuel commun

extension BatterySnapshot {
    /// Couleur du niveau de charge (jauge, teinte d'ambiance).
    var levelColor: Color {
        if percentage <= 10 { .red } else if percentage <= 20 { .orange } else { .green }
    }

    /// Couleur du flux batterie : vert = charge, orange/rouge = décharge.
    var wattsColor: Color {
        if watts > 0.5 { .green } else if watts < -0.5 { percentage <= 20 ? .red : .orange } else { .secondary }
    }

    var stateShortLabel: String {
        switch state {
        case .charging: "En charge"
        case .discharging: "Sur batterie"
        case .full: "Pleine"
        case .pluggedNotCharging: "En pause"
        }
    }

    var wattsLabel: String {
        abs(watts) < 0.05 ? "0 W" : String(format: "%+.1f W", watts)
    }

    var batterySymbol: String {
        if state == .charging { return "battery.100percent.bolt" }
        let levels = [0, 25, 50, 75, 100]
        let nearest = levels.min { abs($0 - percentage) < abs($1 - percentage) } ?? 100
        return "battery.\(nearest)percent"
    }

    /// Valeur principale de la carte « temps restant » : « 3 h 24 », « ∞ », « … ».
    var timeRemainingValue: String {
        guard let minutes = timeRemainingMinutes else {
            return state == .full ? "∞" : "…"
        }
        return "\(minutes / 60) h \(String(format: "%02d", minutes % 60))"
    }

    var timeRemainingCaption: String {
        guard timeRemainingMinutes != nil else {
            return state == .full ? "batterie pleine" : "calcul en cours"
        }
        return state == .charging ? "avant charge complète" : "d'autonomie estimée"
    }
}

// MARK: - Style de carte partagé

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.quinary)
            )
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}
