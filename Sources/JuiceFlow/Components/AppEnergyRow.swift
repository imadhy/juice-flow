import SwiftUI

/// Ligne du classement : icône, nom, barre proportionnelle, puissance.
struct AppEnergyRow: View {
    let app: AppPower
    let maxImpact: Double

    private var color: Color {
        if app.energyImpact < 10 { .green } else if app.energyImpact < 60 { .orange } else { .red }
    }

    var body: some View {
        HStack(spacing: 10) {
            iconView
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                    .font(.callout)
                    .lineLimit(1)
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
                .frame(width: 48, alignment: .trailing)
        }
        // Hauteur constante quelle que soit la présence du sous-titre :
        // évite que la liste change de taille à chaque rafraîchissement.
        .frame(height: 32)
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
        app.energyImpact < 10
            ? String(format: "%.1f", app.energyImpact)
            : String(format: "%.0f", app.energyImpact)
    }
}
