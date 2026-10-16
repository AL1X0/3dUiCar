import Foundation
import Observation
import SpotifyiOS
import UIKit

/// Élément affichable de la bibliothèque / des résultats de recherche Spotify.
struct SpotifyItem: Identifiable, Hashable {
    let id: String          // URI Spotify
    let title: String
    let subtitle: String
    let isContainer: Bool   // dossier / section qu'on ouvre
    let isPlayable: Bool
    var imageURL: URL? = nil
}

struct SpotifySection: Identifiable, Hashable {
    let id: String
    let title: String
    var items: [SpotifyItem]
}

/// Pilote l'app Spotify installée sur l'iPad via le SDK App Remote :
/// lecture, morceau en cours, bibliothèque, recherche (API Web), favoris, aléatoire, répétition.
///
/// Prérequis : app créée sur developer.spotify.com (Client ID intégré au build) avec la
/// redirect URI `car3dui://spotify-login-callback`, et l'app Spotify installée sur l'iPad.
@MainActor
@Observable
final class SpotifyController: NSObject {
    enum Repeat { case off, track, context }

    static let redirectURL = URL(string: "car3dui://spotify-login-callback")!
    private static let clientIDKey = "SpotifyClientID"
    private static let tokenKey = "SpotifyAccessToken"
    private static let tokenDateKey = "SpotifyAccessTokenDate"

    // Lecture en cours
    var title = "Spotify"
    var artist = "Touchez pour connecter"
    var album = ""
    var artwork: UIImage?
    var trackURI: String?
    var isPlaying = false
    var isSaved = false
    var shuffle = false
    var repeatMode: Repeat = .off
    var canSeek = true
    var duration: TimeInterval = 0
    var currentTime: TimeInterval = 0
    var progress: Double { duration > 0 ? min(1, currentTime / duration) : 0 }

    // Connexion
    var isConnected = false
    var lastError: String?

    // Navigation dans la bibliothèque
    var sections: [SpotifySection] = []
    var isLoadingLibrary = false
    var searchResults: [SpotifyItem] = []
    var isSearching = false
    @ObservationIgnored private var images: [String: UIImage] = [:]
    var imageVersion = 0            // force le rafraîchissement des vignettes

    var clientID: String {
        didSet {
            UserDefaults.standard.set(clientID, forKey: Self.clientIDKey)
            appRemote = nil
        }
    }
    var isConfigured: Bool { !clientID.trimmingCharacters(in: .whitespaces).isEmpty }

    @ObservationIgnored private var appRemote: SPTAppRemote?
    @ObservationIgnored private var contentItems: [String: SPTAppRemoteContentItem] = [:]
    @ObservationIgnored private var positionTimer: Timer?

    override init() {
        let bundled = Bundle.main.object(forInfoDictionaryKey: "SpotifyClientID") as? String ?? ""
        let stored = UserDefaults.standard.string(forKey: Self.clientIDKey) ?? ""
        clientID = stored.isEmpty ? bundled : stored
        super.init()
        positionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isPlaying else { return }
                self.currentTime = min(self.duration, self.currentTime + 1)
            }
        }
    }

    private var token: String? { UserDefaults.standard.string(forKey: Self.tokenKey) }

    /// Le jeton App Remote expire au bout d'une heure.
    private var tokenIsFresh: Bool {
        let date = UserDefaults.standard.double(forKey: Self.tokenDateKey)
        return token != nil && Date().timeIntervalSince1970 - date < 3300
    }

    private func remote() -> SPTAppRemote? {
        guard isConfigured else { return nil }
        if let appRemote { return appRemote }
        let config = SPTConfiguration(clientID: clientID, redirectURL: Self.redirectURL)
        let r = SPTAppRemote(configuration: config, logLevel: .error)
        r.connectionParameters.accessToken = token
        r.delegate = self
        appRemote = r
        return r
    }

    // MARK: - Connexion

    /// Ouvre Spotify pour autoriser l'app et reprendre la lecture, puis revient via `handle(url:)`.
    func authorize(playURI: String = "") {
        guard let r = remote() else {
            lastError = "Client ID Spotify manquant (Réglages › Musique)."
            return
        }
        r.authorizeAndPlayURI(playURI, completionHandler: nil)
    }

    /// Connexion silencieuse si le jeton est encore valide, sinon passage par l'app Spotify.
    func connect() {
        guard let r = remote(), !r.isConnected else { return }
        if tokenIsFresh { r.connect() }
    }

    /// Bouton « lecture » quand on n'est pas connecté : réveille Spotify et autorise.
    func ensureConnected() {
        guard !isConnected else { return }
        if tokenIsFresh, let r = remote() { r.connect() } else { authorize() }
    }

    func disconnect() {
        guard let r = appRemote, r.isConnected else { return }
        r.disconnect()
    }

    func handle(url: URL) {
        guard url.scheme == Self.redirectURL.scheme, let r = remote() else { return }
        let params = r.authorizationParameters(from: url)
        if let token = params?[SPTAppRemoteAccessTokenKey] {
            UserDefaults.standard.set(token, forKey: Self.tokenKey)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.tokenDateKey)
            r.connectionParameters.accessToken = token
            r.connect()
        } else if let error = params?[SPTAppRemoteErrorDescriptionKey] {
            lastError = error
        }
    }

    // MARK: - Commandes

    func togglePlay() {
        guard isConnected, let api = appRemote?.playerAPI else { ensureConnected(); return }
        if isPlaying { api.pause(nil) } else { api.resume(nil) }
        isPlaying.toggle()
    }

    func next() { appRemote?.playerAPI?.skip(toNext: nil) }
    func previous() { appRemote?.playerAPI?.skip(toPrevious: nil) }

    func seek(to fraction: Double) {
        guard canSeek, duration > 0 else { return }
        let ms = Int(max(0, min(1, fraction)) * duration * 1000)
        currentTime = Double(ms) / 1000
        appRemote?.playerAPI?.seek(toPosition: ms, callback: nil)
    }

    func toggleShuffle() {
        shuffle.toggle()
        appRemote?.playerAPI?.setShuffle(shuffle, callback: nil)
    }

    func cycleRepeat() {
        repeatMode = switch repeatMode { case .off: .context; case .context: .track; case .track: .off }
        let mode: SPTAppRemotePlaybackOptionsRepeatMode = switch repeatMode {
        case .off: .off
        case .track: .track
        case .context: .context
        }
        appRemote?.playerAPI?.setRepeatMode(mode, callback: nil)
    }

    /// Ajoute / retire le morceau en cours de « Titres likés ».
    func toggleLike() {
        guard let uri = trackURI, let user = appRemote?.userAPI else { return }
        if isSaved { user.removeItemFromLibrary(withURI: uri, callback: nil) }
        else { user.addItemToLibrary(withURI: uri, callback: nil) }
        isSaved.toggle()
    }

    func play(_ item: SpotifyItem) {
        guard isConnected, let api = appRemote?.playerAPI else { authorize(playURI: item.id); return }
        if let content = contentItems[item.id] { api.playItem(content, callback: nil) }
        else { api.play(item.id, callback: nil) }
    }

    // MARK: - Bibliothèque (App Remote)

    func loadLibrary() {
        guard isConnected, let content = appRemote?.contentAPI else { return }
        isLoadingLibrary = true
        content.fetchRecommendedContentItems(forType: SPTAppRemoteContentTypeDefault, flattenContainers: false) { [weak self] result, error in
            let roots = (result as? [SPTAppRemoteContentItem]) ?? []
            Task { @MainActor in
                guard let self else { return }
                self.isLoadingLibrary = false
                if let error { self.lastError = error.localizedDescription }
                self.sections = roots.map { root in
                    self.remember(root)
                    let children = (root.children ?? []).map { self.item(from: $0) }
                    return SpotifySection(id: root.uri, title: root.title ?? "", items: children)
                }
                // Sections sans enfants : on les charge
                for root in roots where (root.children ?? []).isEmpty && root.isContainer {
                    self.loadChildren(of: root.uri)
                }
            }
        }
    }

    /// Charge le contenu d'un dossier (section, playlist…) dans `sections`.
    func loadChildren(of uri: String) {
        guard let parent = contentItems[uri], let content = appRemote?.contentAPI else { return }
        content.fetchChildren(of: parent) { [weak self] result, _ in
            let children = (result as? [SPTAppRemoteContentItem]) ?? []
            Task { @MainActor in
                guard let self else { return }
                let items = children.map { self.item(from: $0) }
                if let i = self.sections.firstIndex(where: { $0.id == uri }) {
                    self.sections[i].items = items
                } else {
                    self.sections.insert(SpotifySection(id: uri, title: parent.title ?? "", items: items), at: 0)
                }
            }
        }
    }

    private func remember(_ c: SPTAppRemoteContentItem) { contentItems[c.uri] = c }

    private func item(from c: SPTAppRemoteContentItem) -> SpotifyItem {
        remember(c)
        return SpotifyItem(id: c.uri, title: c.title ?? "", subtitle: c.subtitle ?? "",
                           isContainer: c.isContainer, isPlayable: c.isPlayable)
    }

    /// Vignette d'un élément (cache) ; charge via App Remote ou URL (résultats de recherche).
    func image(for item: SpotifyItem) -> UIImage? {
        if let img = images[item.id] { return img }
        if let content = contentItems[item.id] {
            appRemote?.imageAPI?.fetchImage(forItem: content, with: CGSize(width: 200, height: 200)) { [weak self] result, _ in
                guard let img = result as? UIImage else { return }
                Task { @MainActor in self?.store(img, for: item.id) }
            }
        } else if let url = item.imageURL {
            Task {
                guard let (data, _) = try? await URLSession.shared.data(from: url), let img = UIImage(data: data) else { return }
                store(img, for: item.id)
            }
        }
        images[item.id] = UIImage()   // évite les requêtes en double
        return nil
    }

    private func store(_ img: UIImage, for id: String) {
        images[id] = img
        imageVersion += 1
    }

    // MARK: - Recherche (API Web Spotify, même jeton)

    func search(_ query: String) async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, let token else { searchResults = []; return }
        isSearching = true
        defer { isSearching = false }
        var comps = URLComponents(string: "https://api.spotify.com/v1/search")!
        comps.queryItems = [
            .init(name: "q", value: q), .init(name: "type", value: "track,album,playlist,artist"),
            .init(name: "limit", value: "8"), .init(name: "market", value: "from_token"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if (response as? HTTPURLResponse)?.statusCode == 401 {
                lastError = "Session Spotify expirée : touche Connecter."
                return
            }
            searchResults = Self.parseSearch(data)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private static func parseSearch(_ data: Data) -> [SpotifyItem] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        var out: [SpotifyItem] = []
        func images(_ o: [String: Any]) -> URL? {
            let imgs = (o["images"] as? [[String: Any]]) ?? ((o["album"] as? [String: Any])?["images"] as? [[String: Any]]) ?? []
            return (imgs.last?["url"] as? String).flatMap(URL.init(string:))
        }
        for (key, label) in [("tracks", "Titre"), ("artists", "Artiste"), ("albums", "Album"), ("playlists", "Playlist")] {
            let items = ((json[key] as? [String: Any])?["items"] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
            for o in items.prefix(key == "tracks" ? 8 : 4) {
                guard let uri = o["uri"] as? String, let name = o["name"] as? String else { continue }
                let artists = (o["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String }.joined(separator: ", ")
                let owner = (o["owner"] as? [String: Any])?["display_name"] as? String
                let sub = [label, artists ?? owner].compactMap { $0 }.joined(separator: " · ")
                out.append(SpotifyItem(id: uri, title: name, subtitle: sub, isContainer: false,
                                       isPlayable: true, imageURL: images(o)))
            }
        }
        return out
    }

    // MARK: - État du lecteur

    private func apply(_ state: SPTAppRemotePlayerState) {
        let track = state.track
        title = track.name
        artist = track.artist.name
        album = track.album.name
        isPlaying = !state.isPaused
        duration = TimeInterval(track.duration) / 1000
        currentTime = TimeInterval(state.playbackPosition) / 1000
        shuffle = state.playbackOptions.isShuffling
        repeatMode = switch state.playbackOptions.repeatMode {
        case .track: .track
        case .context: .context
        default: .off
        }
        canSeek = state.playbackRestrictions.canSeek
        isSaved = track.isSaved
        guard track.uri != trackURI else { return }
        trackURI = track.uri
        appRemote?.imageAPI?.fetchImage(forItem: track, with: CGSize(width: 300, height: 300)) { [weak self] result, _ in
            guard let image = result as? UIImage else { return }
            Task { @MainActor in self?.artwork = image }
        }
    }
}

extension SpotifyController: SPTAppRemoteDelegate, SPTAppRemotePlayerStateDelegate {
    nonisolated func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        Task { @MainActor in
            isConnected = true
            lastError = nil
            appRemote.playerAPI?.delegate = self
            appRemote.playerAPI?.subscribe(toPlayerState: nil)
            appRemote.playerAPI?.getPlayerState { [weak self] result, _ in
                guard let state = result as? SPTAppRemotePlayerState else { return }
                Task { @MainActor in self?.apply(state) }
            }
            loadLibrary()
        }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        Task { @MainActor in
            isConnected = false
            lastError = "Spotify non joignable : touche Connecter."
        }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
        Task { @MainActor in
            isConnected = false
            isPlaying = false
        }
    }

    nonisolated func playerStateDidChange(_ playerState: SPTAppRemotePlayerState) {
        Task { @MainActor in apply(playerState) }
    }
}
