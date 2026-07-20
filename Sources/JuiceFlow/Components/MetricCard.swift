import SwiftUI

/// Carte métrique du layout bento : icône teintée, titre, valeur, sous-titre.
struct MetricCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.callout)
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())

            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        // Hauteur uniforme : les cartes du bento restent alignées entre elles.
        .frame(minHeight: 88, alignment: .topLeading)
        .card()
    }
}
