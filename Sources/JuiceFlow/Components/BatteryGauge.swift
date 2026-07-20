import SwiftUI

/// Jauge circulaire : l'anneau représente le niveau de charge ; le centre
/// affiche l'autonomie restante quand elle est la vraie information
/// (sur batterie), sinon le pourcentage.
struct BatteryGauge: View {
    let snapshot: BatterySnapshot
    var size: CGFloat = 190
    /// Texte héros au centre (ex : « 4 h 32 ») ; nil → pourcentage en héros.
    var heroText: String?

    private var fraction: Double { Double(snapshot.percentage) / 100 }
    private var color: Color { snapshot.levelColor }
    private var lineWidth: CGFloat { size * 0.085 }

    var body: some View {
        ZStack {
            // Halo d'ambiance : dégradé radial statique — pas de blur(),
            // dont la convolution se repayait à chaque frame d'animation.
            Circle()
                .fill(RadialGradient(
                    colors: [color.opacity(0.30), color.opacity(0)],
                    center: .center,
                    startRadius: size * 0.28,
                    endRadius: size * 0.72
                ))
                .padding(-size * 0.18)

            Circle()
                .stroke(Color.primary.opacity(0.07),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    AngularGradient(
                        colors: [color.opacity(0.45), color],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360 * fraction)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.35), radius: size * 0.037)

            center
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private var center: some View {
        if let heroText {
            VStack(spacing: 2) {
                Text(heroText)
                    .font(.system(size: size * 0.2, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("\(snapshot.percentage) % · \(snapshot.stateShortLabel)")
                    .font(.system(size: size * 0.065, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(snapshot.percentage)")
                        .font(.system(size: size * 0.25, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("%")
                        .font(.system(size: size * 0.11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                // Illisible sous ~100 pt (version mini de la barre des menus).
                if size >= 100 {
                    HStack(spacing: 3) {
                        if snapshot.state == .charging {
                            Image(systemName: "bolt.fill")
                                .foregroundStyle(.green)
                        }
                        Text(snapshot.stateShortLabel)
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: size * 0.062, weight: .medium))
                }
            }
        }
    }
}
