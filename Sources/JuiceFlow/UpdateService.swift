import AppKit
import Observation

/// Mise à jour OTA depuis les releases GitHub, sans dépendance : l'API
/// publique `releases/latest` donne la version, les notes et le .zip.
///
/// Modèle de confiance : le même que le téléchargement initial — TLS vers
/// github.com et intégrité du dépôt. Un téléchargement URLSession ne pose
/// pas de quarantaine, la signature ad-hoc n'est donc pas un obstacle
/// (Gatekeeper n'examine que les fichiers en quarantaine).
///
/// Installation : le .zip est extrait avec `ditto` (préserve la signature),
/// le bundle validé (identifiant + version), l'ancienne version part à la
/// corbeille, la nouvelle prend sa place et l'app se relance.
@MainActor
@Observable
final class UpdateService {
    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case installing(Release)
        case failed(String, pageURL: URL?)
    }

    struct Release: Equatable, Sendable {
        var version: String     // « 0.2.0 » (tag sans le « v »)
        var notes: String
        var zipURL: URL?        // absent si la release n'a pas d'asset .zip
        var pageURL: URL
    }

    private(set) var phase: Phase = .idle

    @ObservationIgnored private var checkTask: Task<Void, Never>?
    @ObservationIgnored private var lastCheck: ContinuousClock.Instant?

    /// Hors bundle (`swift run`), se mettre à jour n'a pas de sens.
    nonisolated static var isBundled: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    nonisolated static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    nonisolated static let defaultFeed =
        URL(string: "https://api.github.com/repos/imadhy/juice-flow/releases/latest")!

    /// Surchageable pour les tests : JUICEFLOW_UPDATE_FEED=file:///…/latest.json
    nonisolated static var feedURL: URL {
        if let raw = ProcessInfo.processInfo.environment["JUICEFLOW_UPDATE_FEED"],
           let url = URL(string: raw) {
            return url
        }
        return defaultFeed
    }

    init() {
        guard Self.isBundled else { return }
        // Vérification discrète au lancement puis quotidienne : ne dérange
        // que s'il y a du nouveau (la phase passe à `available`).
        checkTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            while !Task.isCancelled {
                await self?.checkQuietly()
                try? await Task.sleep(for: .seconds(24 * 3600), tolerance: .seconds(3600))
            }
        }
    }

    // MARK: - Vérification

    /// Vérification opportuniste à l'ouverture d'une vue (fenêtre, popover) :
    /// silencieuse, et au plus une par heure — la boucle quotidienne reste
    /// le filet, ceci rend juste la découverte plus rapide.
    func checkIfStale() {
        guard Self.isBundled else { return }
        if let lastCheck, lastCheck.duration(to: .now) < .seconds(3600) { return }
        Task { await checkQuietly() }
    }

    /// Vérification manuelle (bouton des Réglages) : toutes les issues
    /// sont montrées, y compris « à jour » et les erreurs.
    func check() async {
        phase = .checking
        lastCheck = .now
        do {
            let release = try await Self.fetchLatest(from: Self.feedURL)
            phase = Self.isNewer(release.version, than: Self.currentVersion)
                ? .available(release) : .upToDate
        } catch {
            phase = .failed(error.localizedDescription, pageURL: Self.releasesPage)
        }
    }

    /// Vérification de fond : silencieuse sauf si une version plus récente
    /// existe. Ne touche pas une installation en cours.
    private func checkQuietly() async {
        guard phase == .idle || phase == .upToDate else { return }
        lastCheck = .now
        guard let release = try? await Self.fetchLatest(from: Self.feedURL),
              Self.isNewer(release.version, than: Self.currentVersion) else { return }
        phase = .available(release)
    }

    // MARK: - Installation

    /// Télécharge, remplace le bundle et relance l'app. En cas d'échec,
    /// l'app en place reste intacte (le remplacement est la toute
    /// dernière étape).
    func install() async {
        guard case .available(let release) = phase else { return }
        phase = .installing(release)
        do {
            try await Self.downloadAndInstall(release, replacing: Bundle.main.bundleURL)
            relaunch()
        } catch {
            phase = .failed(error.localizedDescription, pageURL: release.pageURL)
        }
    }

    /// Relance le bundle (fraîchement remplacé) dès que ce processus meurt.
    private func relaunch() {
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = [
            "-c", #"while kill -0 "$1" 2>/dev/null; do sleep 0.2; done; open "$2""#,
            "_", "\(ProcessInfo.processInfo.processIdentifier)", Bundle.main.bundleURL.path,
        ]
        try? helper.run()
        NSApp.terminate(nil)
    }

    // MARK: - Mécanique partagée (GUI + CLI --check-update/--install-update)

    nonisolated static var releasesPage: URL {
        URL(string: "https://github.com/imadhy/juice-flow/releases")!
    }

    private struct GitHubRelease: Decodable {
        let tagName: String
        let body: String?
        let htmlUrl: URL
        let assets: [Asset]
        struct Asset: Decodable {
            let name: String
            let browserDownloadUrl: URL
        }
    }

    nonisolated static func fetchLatest(from feed: URL) async throws -> Release {
        do {
            return try await fetchFromAPI(feed)
        } catch {
            // L'API non authentifiée est limitée à 60 req/h PAR IP : sur un
            // réseau partagé le quota peut être épuisé par d'autres. Repli
            // sans quota via la redirection de /releases/latest — mais pas
            // pour un feed de test, qui doit rester hermétique.
            guard feed == defaultFeed else { throw error }
            return try await fetchFromRedirect()
        }
    }

    private nonisolated static func fetchFromAPI(_ feed: URL) async throws -> Release {
        var request = URLRequest(url: feed)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw UpdateError("GitHub a répondu \(http.statusCode) — réessayez plus tard.")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let github = try decoder.decode(GitHubRelease.self, from: data)
        let version = github.tagName.hasPrefix("v")
            ? String(github.tagName.dropFirst()) : github.tagName
        return Release(
            version: version,
            notes: github.body ?? "",
            zipURL: github.assets.first { $0.name.hasSuffix(".zip") }?.browserDownloadUrl,
            pageURL: github.htmlUrl
        )
    }

    /// Sans l'API : /releases/latest redirige vers /releases/tag/vX.Y.Z, et
    /// le .zip suit la convention de make-dmg.sh (JuiceFlow-X.Y.Z.zip). Son
    /// existence est sondée en HEAD pour ne rien promettre d'introuvable.
    private nonisolated static func fetchFromRedirect() async throws -> Release {
        let latest = URL(string: "https://github.com/imadhy/juice-flow/releases/latest")!
        let (_, response) = try await URLSession.shared.data(from: latest)
        guard let page = response.url, page.path.contains("/releases/tag/") else {
            throw UpdateError("Impossible de déterminer la dernière release.")
        }
        let tag = page.lastPathComponent
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let zip = URL(string:
            "https://github.com/imadhy/juice-flow/releases/download/\(tag)/JuiceFlow-\(version).zip")!

        var probe = URLRequest(url: zip)
        probe.httpMethod = "HEAD"
        let zipExists = await (try? URLSession.shared.data(for: probe))
            .flatMap { ($0.1 as? HTTPURLResponse)?.statusCode } == 200
        return Release(version: version, notes: "",
                       zipURL: zipExists ? zip : nil, pageURL: page)
    }

    /// « 0.10.1 » > « 0.9.9 » : comparaison numérique composant par
    /// composant, pas alphabétique.
    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ v: String) -> [Int] {
            v.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        }
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// Télécharge le .zip, valide le bundle extrait et remplace `bundleURL`.
    /// L'ancienne version part à la corbeille (récupérable).
    nonisolated static func downloadAndInstall(
        _ release: Release, replacing bundleURL: URL
    ) async throws {
        guard let zipURL = release.zipURL else {
            throw UpdateError("La release \(release.version) n'a pas d'archive .zip — installez-la depuis la page GitHub.")
        }
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("juiceflow-update")
        try? fm.removeItem(at: work)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        let (downloaded, response) = try await URLSession.shared.download(from: zipURL)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw UpdateError("Téléchargement refusé (HTTP \(http.statusCode)).")
        }
        let zip = work.appendingPathComponent("update.zip")
        try fm.moveItem(at: downloaded, to: zip)

        // ditto préserve liens symboliques et signature, contrairement à unzip.
        let staged = work.appendingPathComponent("staged")
        let ditto = try await PowerMetricsService.run(
            "/usr/bin/ditto", ["-x", "-k", zip.path, staged.path])
        guard ditto.status == 0 else {
            throw UpdateError("Extraction impossible : \(ditto.output.prefix(200))")
        }
        guard let app = try fm.contentsOfDirectory(at: staged, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" }) else {
            throw UpdateError("L'archive ne contient pas d'application.")
        }

        // Garde-fou : même identifiant et version annoncée, sinon on ne
        // touche à rien.
        guard let info = Bundle(url: app)?.infoDictionary,
              info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
              info["CFBundleShortVersionString"] as? String == release.version else {
            throw UpdateError("Le bundle téléchargé ne correspond pas à la release annoncée.")
        }

        try fm.trashItem(at: bundleURL, resultingItemURL: nil)
        do {
            try fm.moveItem(at: app, to: bundleURL)
        } catch {
            // tmp sur un autre volume que l'app : la copie fait l'affaire.
            try fm.copyItem(at: app, to: bundleURL)
        }
    }

    struct UpdateError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
