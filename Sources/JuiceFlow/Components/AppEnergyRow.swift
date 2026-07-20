import SwiftUI

/// Ligne du classement : icône, nom, barre proportionnelle, puissance.
struct AppEnergyRow: View {
    let app: AppPower
    let maxImpact: Double
    var isSelected = false
    @State private var isHovering = false

    private var color: Color {
        if let watts = app.watts {
            // Mode précision : seuils en watts réels.
            if watts < 0.5 { .green } else if watts < 2.5 { .orange } else { .red }
        } else {
            if app.energyImpact < 10 { .green } else if app.energyImpact < 60 { .orange } else { .red }
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            iconView
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(app.name)
                        .font(.callout)
                        .lineLimit(1)
                    if app.isRunaway {
                        badge("flame.fill", .red, help: "Consommation en forte hausse")
                    }
                    if app.isBackgroundActive {
                        badge("moon.fill", .indigo, help: "Consomme en arrière-plan")
                    }
                }
                if app.processCount > 1 {
                    Text("\(app.processCount) processus")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 12)

            bar

            Text(impactText)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .frame(width: 56, alignment: .trailing)
        }
        // Hauteur constante quelle que soit la présence du sous-titre :
        // évite que la liste change de taille à chaque rafraîchissement.
        .frame(height: 34)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected
                      ? Color.accentColor.opacity(0.16)
                      : isHovering ? Color.primary.opacity(0.06) : .clear)
        )
        .padding(.horizontal, -6)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    /// Pastille pleine : glyphe blanc sur cercle coloré — visible au premier
    /// coup d'œil, contrairement aux petites icônes teintées.
    private func badge(_ symbol: String, _ color: Color, help: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 8.5, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 15, height: 15)
            .background(Circle().fill(color.gradient))
            .help(help)
    }

    @ViewBuilder
    private var iconView: some View {
        if let icon = app.icon {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
    }

    private var bar: some View {
        Capsule()
            .fill(.quinary)
            .frame(width: 84, height: 6)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(color.gradient)
                    .frame(width: max(84 * app.energyImpact / max(maxImpact, 0.001), 5), height: 6)
            }
    }

    private var impactText: String {
        if let watts = app.watts {
            return watts < 1
                ? String(format: "%.0f mW", watts * 1000)
                : String(format: "%.1f W", watts)
        }
        return app.energyImpact < 10
            ? String(format: "%.1f", app.energyImpact)
            : String(format: "%.0f", app.energyImpact)
    }
}
