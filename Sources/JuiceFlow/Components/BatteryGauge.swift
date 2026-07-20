import SwiftUI

/// Jauge circulaire du niveau de batterie : anneau à dégradé angulaire,
/// pourcentage géant au centre, état résumé en dessous.
struct BatteryGauge: View {
    let snapshot: BatterySnapshot

    private var fraction: Double { Double(snapshot.percentage) / 100 }
    private var color: Color { snapshot.levelColor }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.07), style: StrokeStyle(lineWidth: 16, lineCap: .round))

            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    AngularGradient(
                        colors: [color.opacity(0.45), color],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360 * fraction)
                    ),
                    style: StrokeStyle(lineWidth: 16, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.35), radius: 7)

            VStack(spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(snapshot.percentage)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("%")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 3) {
                    if snapshot.state == .charging {
                        Image(systemName: "bolt.fill")
                            .foregroundStyle(.green)
                    }
                    Text(snapshot.stateShortLabel)
                        .foregroundStyle(.secondary)
                }
                .font(.caption.weight(.medium))
            }
        }
        .frame(width: 190, height: 190)
    }
}
