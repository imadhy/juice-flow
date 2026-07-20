import SwiftUI

/// Accueil de première ouverture : ce que fait l'app, en trois idées,
/// et le raccourci vers le mode précision.
struct OnboardingView: View {
    @Environment(ProcessService.self) private var processes
    let done: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.02, green: 0.23, blue: 0.16),
                                              Color(red: 0.10, green: 0.72, blue: 0.42)],
                                     startPoint: .bottom, endPoint: .top))
                .frame(width: 68, height: 68)
                .overlay {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                }

            VStack(spacing: 6) {
                Text("Bienvenue dans JuiceFlow")
                    .font(.title2.bold())
                Text("Comprenez en un clin d'œil ce qui consomme votre batterie.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 16) {
                feature("gauge.with.needle", .green, "Tout en temps réel",
                        "Autonomie, flux d'énergie chargeur → Mac → batterie, et le classement des apps gourmandes.")
                feature("scope", .teal, "Des watts exacts, app par app",
                        "Le mode précision utilise powermetrics, l'outil de mesure d'Apple — et chiffre ce que chaque app vous coûte en minutes d'autonomie.")
                feature("bell.badge", .indigo, "Un garde du corps discret",
                        "Dans la barre des menus en permanence ; il vous prévient quand une app s'emballe sur batterie, avec le bouton Quitter dans la notification.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if case .unavailable = processes.powerMetrics.state {
                Button("Activer le mode précision…") {
                    Task { await processes.powerMetrics.installAuthorizationAndStart() }
                }
            }

            Button("C'est parti") { done() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(28)
        .frame(width: 470)
    }

    private func feature(_ icon: String, _ color: Color, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color.opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                Text(text).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
