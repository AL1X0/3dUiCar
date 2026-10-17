import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import Security
import UIKit

/// Élément affichable de la bibliothèque / des résultats de recherche Spotify.
struct SpotifyItem: Identifiable, Hashable {
    let id: String          // URI Spotify (spotify:track:…, spotify:playlist:…)
    let title: String
    let subtitle: String
    let isContainer: Bool   // playlist / album : lecture du contexte
    let isPlayable: Bool
    var imageURL: URL? = nil
}

/// Appareil Spotify Connect (iPad, iPhone, ordinateur, enceinte…).
struct SpotifyDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let type: String
    let isActive: Bool

    var symbol: String {
        switch type.lowercased() {
        case "tablet": "ipad.landscape"
        case "smartphone": "iphone"
        case "computer": "laptopcomputer"
        case "speaker": "hifispeaker.fill"
        case "tv": "tv"
        case "automobile": "car.fill"
        default: "speaker.wave.2.fill"
        }
    }
}

struct SpotifySection: Identifiable, Hashable {
    let id: String
    let title: String
    var items: [SpotifyItem]
}

/// Spotify via l'API Web officielle, connexion OAuth PKCE (sans serveur) :
/// - jeton renouvelé automatiquement avec le refresh token (plus de déconnexion toutes les heures) ;
/// - état de lecture interrogé toutes les 2 s (aucune liaison permanente qui « saute ») ;
/// - commandes, bibliothèque, recherche, favoris via l'API Web (Spotify Premium requis pour piloter).
/// La lecture se fait dans l'app Spotify de l'iPad (ou tout appareil Spotify Connect actif).
@MainActor
@Observable
final class SpotifyController: NSObject {
    enum Repeat: String { case off, track, context }

    static let redirectURI = "car3dui://spotify-login-callback"
    private static let scopes = [
        "user-read-playback-state", "user-modify-playback-state", "user-read-currently-playing",
        "user-library-read", "user-library-modify", "playlist-read-private", "user-read-recently-played",
    ].joined(separator: " ")

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
    var deviceName: String?
    var progress: Double { duration > 0 ? min(1, currentTime / duration) : 0 }

    // Connexion
    private(set) var isConnected = false      // compte autorisé + API joignable
    var lastError: String?

    // Bibliothèque / recherche
    var sections: [SpotifySection] = []
    var isLoadingLibrary = false
    var searchResults: [SpotifyItem] = []
    var isSearching = false

    // Appareils Spotify Connect
    var devices: [SpotifyDevice] = []
    /// Appareil choisi dans « Lire sur… » (mémorisé) ; nil = automatique (iPad en priorité).
    var preferredDeviceID: String? {
        didSet { UserDefaults.standard.set(preferredDeviceID, forKey: "SpotifyPreferredDevice") }
    }

    var clientID: String {
        didSet { UserDefaults.standard.set(clientID, forKey: "SpotifyClientID") }
    }
    var isConfigured: Bool { !clientID.trimmingCharacters(in: .whitespaces).isEmpty }

    @ObservationIgnored private var accessToken: String?
    @ObservationIgnored private var tokenExpiry = Date.distantPast
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var authSession: ASWebAuthenticationSession?
    @ObservationIgnored private var imageCache = NSCache<NSURL, UIImage>()
    @ObservationIgnored private var lastPoll = Date.distantPast
    @ObservationIgnored private var consecutiveFailures = 0
    @ObservationIgnored private var activeDeviceID: String?
    @ObservationIgnored private var pendingPlay: (body: [String: Any]?, label: String)?
    @ObservationIgnored private var likesCheckAvailable = true
    @ObservationIgnored private var likedIDs: Set<String> = []
    @ObservationIgnored private var lastLibraryLoad = Date.distantPast
    @ObservationIgnored private let waker = SpotifyWaker()
    @ObservationIgnored private var lastDevicesLoad = Date.distantPast

    override init() {
        let bundled = Bundle.main.object(forInfoDictionaryKey: "SpotifyClientID") as? String ?? ""
        let stored = UserDefaults.standard.string(forKey: "SpotifyClientID") ?? ""
        clientID = stored.isEmpty ? bundled : stored
        preferredDeviceID = UserDefaults.standard.string(forKey: "SpotifyPreferredDevice")
        super.init()
        isConnected = Keychain.get("spotify.refresh") != nil
        Log.info(.spotify, "Init · client \(clientID.prefix(6))… · compte \(isConnected ? "mémorisé" : "non connecté")")
    }

    // MARK: - Cycle de vie

    /// Démarre l'interrogation de l'état (appelé au premier plan).
    func connect() {
        guard Keychain.get("spotify.refresh") != nil, pollTask == nil else { return }
        Log.info(.spotify, "Interrogation de l'état démarrée")
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshState()
                let delay: Double = (self?.isPlaying ?? false) ? 2 : 4
                try? await Task.sleep(for: .seconds(delay))
            }
        }
        if Date().timeIntervalSince(lastLibraryLoad) > 600 || sections.isEmpty {
            Task { await loadLibrary() }
        }
        if let pending = pendingPlay {
            // Retour depuis l'app Spotify : elle est maintenant un appareil actif
            pendingPlay = nil
            Log.info(.spotify, "Reprise de la lecture en attente : \(pending.label)")
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                await startPlayback(pending.body, label: pending.label, allowOpenApp: false)
            }
        }
    }

    func disconnect() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Bouton lecture quand rien n'est connecté : lance l'autorisation.
    func ensureConnected() {
        if Keychain.get("spotify.refresh") == nil { authorize() } else { connect() }
    }

    func logout() {
        disconnect()
        Keychain.delete("spotify.refresh")
        accessToken = nil
        isConnected = false
        title = "Spotify"
        artist = "Touchez pour connecter"
        artwork = nil
        Log.info(.spotify, "Déconnexion du compte")
    }

    // MARK: - Autorisation PKCE

    func authorize() {
        guard isConfigured else { lastError = "Client ID Spotify manquant."; return }
        let verifier = Self.randomString(64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        var comps = URLComponents(string: "https://accounts.spotify.com/authorize")!
        comps.queryItems = [
            .init(name: "client_id", value: clientID), .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: Self.redirectURI), .init(name: "scope", value: Self.scopes),
            .init(name: "code_challenge_method", value: "S256"), .init(name: "code_challenge", value: challenge),
        ]
        Log.info(.spotify, "Ouverture de l'autorisation Spotify")
        let session = ASWebAuthenticationSession(url: comps.url!, callbackURLScheme: "car3dui") { [weak self] url, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    Log.warning(.spotify, "Autorisation annulée : \(error.localizedDescription)")
                    self.lastError = "Connexion annulée"
                    return
                }
                guard let url, let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                        .queryItems?.first(where: { $0.name == "code" })?.value else {
                    self.lastError = "Réponse Spotify invalide"
                    Log.error(.spotify, "Callback sans code : \(url?.absoluteString ?? "nil")")
                    return
                }
                await self.exchange(code: code, verifier: verifier)
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        authSession = session
        session.start()
    }

    /// Compatibilité : l'ancien flux App Remote revenait par URL ; plus utilisé.
    func handle(url: URL) {
        guard url.scheme == "car3dui" else { return }
        Log.info(.spotify, "Retour automatique depuis Spotify")
        Task {
            try? await Task.sleep(for: .milliseconds(800))
            await refreshState()
        }
    }

    private func exchange(code: String, verifier: String) async {
        let body = [
            "grant_type": "authorization_code", "code": code, "redirect_uri": Self.redirectURI,
            "client_id": clientID, "code_verifier": verifier,
        ]
        if await requestToken(body) {
            Log.info(.spotify, "Compte autorisé")
            connect()
        }
    }

    private func refreshAccessToken() async -> Bool {
        guard let refresh = Keychain.get("spotify.refresh") else { return false }
        return await requestToken(["grant_type": "refresh_token", "refresh_token": refresh, "client_id": clientID])
    }

    private func requestToken(_ form: [String: String]) async -> Bool {
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = form.map { "\($0.key)=\($0.value.formEncoded)" }.joined(separator: "&").data(using: .utf8)
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200, let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = json["access_token"] as? String else {
                let text = String(decoding: data.prefix(200), as: UTF8.self)
                Log.error(.spotify, "Jeton refusé (\(status)) : \(text)")
                if status == 400 || status == 401 {
                    // refresh token révoqué : il faudra se reconnecter
                    Keychain.delete("spotify.refresh")
                    isConnected = false
                    lastError = "Session Spotify expirée : reconnecte-toi."
                }
                return false
            }
            accessToken = token
            tokenExpiry = Date().addingTimeInterval(Double(json["expires_in"] as? Int ?? 3600) - 120)
            if let refresh = json["refresh_token"] as? String { Keychain.set(refresh, for: "spotify.refresh") }
            isConnected = true
            lastError = nil
            Log.info(.spotify, "Jeton obtenu, valide jusqu'à \(tokenExpiry.formatted(date: .omitted, time: .shortened))")
            return true
        } catch {
            Log.warning(.spotify, "Réseau indisponible pour le jeton : \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Client API Web

    @discardableResult
    private func api(_ method: String, _ path: String, query: [String: String] = [:],
                     body: [String: Any]? = nil) async -> (Int, Data?) {
        if accessToken == nil || Date() > tokenExpiry {
            guard await refreshAccessToken() else { return (401, nil) }
        }
        var comps = URLComponents(string: "https://api.spotify.com/v1" + path)!
        if !query.isEmpty { comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.timeoutInterval = 8
        req.setValue("Bearer \(accessToken ?? "")", forHTTPHeaderField: "Authorization")
        if let body {
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        } else if method != "GET" {
            req.httpBody = Data()
        }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401, await refreshAccessToken() {
                return await api(method, path, query: query, body: body)
            }
            if status >= 400 {
                let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                    .flatMap { ($0["error"] as? [String: Any])?["message"] as? String } ?? ""
                Log.warning(.spotify, "\(method) \(path) → \(status) \(msg)")
                if status == 403 { lastError = "Spotify Premium requis pour piloter la lecture." }
                if status == 404, msg.lowercased().contains("device") { lastError = "Aucun appareil Spotify actif : ouvre Spotify." }
                if status == 429 { lastError = "Spotify limite les requêtes, nouvel essai bientôt." }
            }
            consecutiveFailures = 0
            return (status, data)
        } catch {
            consecutiveFailures += 1
            if consecutiveFailures == 1 || consecutiveFailures % 10 == 0 {
                Log.warning(.spotify, "\(method) \(path) : \(error.localizedDescription) (×\(consecutiveFailures))")
            }
            return (0, nil)
        }
    }

    // MARK: - État de lecture

    func refreshState() async {
        if Date().timeIntervalSince(lastDevicesLoad) > 20 { _ = await fetchDevices() }
        let (status, data) = await api("GET", "/me/player", query: ["additional_types": "episode"])
        lastPoll = Date()
        if status == 204 {
            activeDeviceID = nil
            // Rien en cours sur aucun appareil
            if isPlaying { Log.info(.spotify, "Aucune lecture active") }
            isPlaying = false
            deviceName = nil
            if title == "Spotify" { artist = "Aucune lecture · ouvre Spotify" }
            return
        }
        guard status == 200, let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        isPlaying = json["is_playing"] as? Bool ?? false
        shuffle = json["shuffle_state"] as? Bool ?? false
        repeatMode = Repeat(rawValue: json["repeat_state"] as? String ?? "off") ?? .off
        currentTime = Double(json["progress_ms"] as? Int ?? 0) / 1000
        let device = json["device"] as? [String: Any]
        deviceName = device?["name"] as? String
        activeDeviceID = device?["id"] as? String
        let disallows = (json["actions"] as? [String: Any])?["disallows"] as? [String: Any]
        canSeek = !(disallows?["seeking"] as? Bool ?? false)
        guard let item = json["item"] as? [String: Any] else { return }
        title = item["name"] as? String ?? ""
        artist = (item["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String }.joined(separator: ", ")
            ?? ((item["show"] as? [String: Any])?["name"] as? String ?? "")
        album = (item["album"] as? [String: Any])?["name"] as? String ?? ""
        duration = Double(item["duration_ms"] as? Int ?? 0) / 1000
        let uri = item["uri"] as? String
        if uri != trackURI {
            trackURI = uri
            Log.info(.spotify, "Lecture : \(title) — \(artist) (\(deviceName ?? "?"))")
            let images = ((item["album"] as? [String: Any])?["images"] as? [[String: Any]]) ?? []
            if let s = images.first?["url"] as? String, let url = URL(string: s) {
                artwork = await image(url: url)
            }
            if let id = item["id"] as? String {
                isSaved = likedIDs.contains(id)
                if likesCheckAvailable {
                    let (status, d) = await api("GET", "/me/tracks/contains", query: ["ids": id])
                    if status == 403 {
                        likesCheckAvailable = false
                        Log.info(.spotify, "Vérification des favoris refusée par Spotify : déduite de « Titres likés »")
                    } else if let v = (d.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [Bool] })?.first {
                        isSaved = v
                    }
                }
            }
        }
    }

    /// Après une commande : état rafraîchi rapidement.
    private func refreshSoon() {
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            await refreshState()
        }
    }

    // MARK: - Commandes

    func togglePlay() {
        guard isConnected else { authorize(); return }
        if isPlaying {
            isPlaying = false
            Task {
                let (status, _) = await api("PUT", "/me/player/pause")
                if status == 403 { Log.debug(.spotify, "Pause refusée (déjà en pause ?) : resynchronisation") }
                refreshSoon()
            }
        } else {
            isPlaying = true
            Task { await startPlayback(nil, label: "reprise", allowOpenApp: true) }
        }
    }

    func next() { skip("/me/player/next") }
    func previous() { skip("/me/player/previous") }

    private func skip(_ path: String) {
        Task {
            let (status, _) = await api("POST", path)
            if status == 403 { lastError = "Pas de titre suivant/précédent dans cette lecture." }
            if status == 404 { lastError = "Aucun appareil Spotify actif." }
            refreshSoon()
        }
    }

    func seek(to fraction: Double) {
        guard canSeek, duration > 0 else { return }
        let ms = Int(max(0, min(1, fraction)) * duration * 1000)
        currentTime = Double(ms) / 1000
        Task { await api("PUT", "/me/player/seek", query: ["position_ms": "\(ms)"]) }
    }

    func toggleShuffle() {
        shuffle.toggle()
        let value = shuffle
        Task { await api("PUT", "/me/player/shuffle", query: ["state": value ? "true" : "false"]) }
    }

    func cycleRepeat() {
        repeatMode = switch repeatMode { case .off: .context; case .context: .track; case .track: .off }
        let value = repeatMode.rawValue
        Task { await api("PUT", "/me/player/repeat", query: ["state": value]) }
    }

    func toggleLike() {
        guard let uri = trackURI, let id = uri.split(separator: ":").last.map(String.init) else { return }
        let save = !isSaved
        isSaved = save
        Task {
            let (status, _) = await api(save ? "PUT" : "DELETE", "/me/tracks", query: ["ids": id])
            if (200..<300).contains(status) {
                if save { likedIDs.insert(id) } else { likedIDs.remove(id) }
                Log.info(.spotify, save ? "Ajouté aux titres likés" : "Retiré des titres likés")
            } else {
                isSaved = !save
                lastError = status == 403 ? "Spotify refuse la modification des favoris pour cette app." : "Favori non enregistré."
            }
        }
    }

    /// Lance un élément. Pour un titre, toute la liste affichée devient la file d'attente
    /// (sinon « suivant » est impossible : erreur 403 « Restriction violated »).
    func play(_ item: SpotifyItem, in list: [SpotifyItem] = []) {
        guard isConnected else { authorize(); return }
        let isTrack = item.id.contains(":track:") || item.id.contains(":episode:")
        let body: [String: Any]
        if isTrack {
            let queue = list.map(\.id).filter { $0.contains(":track:") || $0.contains(":episode:") }
            let uris = queue.contains(item.id) ? Array(queue.prefix(100)) : [item.id]
            body = ["uris": uris, "offset": ["uri": item.id]]
        } else {
            body = ["context_uri": item.id]
        }
        Log.info(.spotify, "Lecture demandée : \(item.title)")
        Task { await startPlayback(body, label: item.title, allowOpenApp: true) }
    }

    /// Démarre / reprend la lecture en visant explicitement un appareil :
    /// 1. appareil actif ; 2. sinon l'iPad (ou le 1er appareil Spotify Connect) via `device_id` ;
    /// 3. sinon ouverture de l'app Spotify, et la lecture reprend au retour dans l'app.
    private func startPlayback(_ body: [String: Any]?, label: String, allowOpenApp: Bool) async {
        // 1. Appareil actif (sauf si l'utilisateur a choisi un autre appareil)
        if let active = activeDeviceID, preferredDeviceID == nil || preferredDeviceID == active {
            let (status, _) = await api("PUT", "/me/player/play", body: body)
            if (200..<300).contains(status) { lastError = nil; refreshSoon(); return }
            if status != 404 { refreshSoon(); return }
        }
        // 2. Appareil choisi, sinon l'iPad, sinon le premier disponible, via device_id
        let list = await fetchDevices()
        if let target = pickDevice(list) {
            for attempt in 0..<3 {
                let (status, _) = await api("PUT", "/me/player/play", query: ["device_id": target.id], body: body)
                if (200..<300).contains(status) {
                    activeDeviceID = target.id
                    lastError = nil
                    Log.info(.spotify, "Lecture sur « \(target.name) »")
                    refreshSoon()
                    return
                }
                if status != 404 && status != 502 { break }
                try? await Task.sleep(for: .milliseconds(600 * (attempt + 1)))
            }
        }
        // 3. Aucun appareil : Spotify dort sur l'iPad → réveil express (retour automatique ici)
        guard allowOpenApp else {
            lastError = "Spotify ne répond pas. Réessaie dans un instant."
            return
        }
        guard waker.isInstalled else {
            lastError = "Installe l'app Spotify sur l'iPad (elle joue le son en arrière-plan)."
            return
        }
        let uri = (body?["context_uri"] as? String) ?? ((body?["uris"] as? [String])?.first) ?? ""
        // Après le retour, on renvoie la file d'attente complète (titres) ; un contexte joue déjà.
        pendingPlay = body?["uris"] != nil ? (body, label) : nil
        lastError = nil
        waker.wake(clientID: clientID, playURI: uri)
    }

    /// Choix de l'appareil : préféré → iPad → actif → premier.
    private func pickDevice(_ list: [SpotifyDevice]) -> SpotifyDevice? {
        if let pref = preferredDeviceID, let d = list.first(where: { $0.id == pref }) { return d }
        return list.first { $0.type.lowercased() == "tablet" } ?? list.first { $0.isActive } ?? list.first
    }

    /// « Lire sur… » : transfère la lecture en cours vers l'appareil choisi.
    func transfer(to device: SpotifyDevice?) {
        preferredDeviceID = device?.id
        guard let device else { return }
        Log.info(.spotify, "Lecture transférée vers « \(device.name) »")
        Task {
            await api("PUT", "/me/player", body: ["device_ids": [device.id], "play": isPlaying])
            refreshSoon()
        }
    }

    func reloadDevices() { Task { _ = await fetchDevices() } }

    private func fetchDevices() async -> [SpotifyDevice] {
        lastDevicesLoad = Date()
        let (_, data) = await api("GET", "/me/player/devices")
        let raw = (data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["devices"] as? [[String: Any]]) ?? []
        let list = raw.compactMap { d -> SpotifyDevice? in
            guard let id = d["id"] as? String else { return nil }
            return SpotifyDevice(id: id, name: d["name"] as? String ?? "?", type: d["type"] as? String ?? "",
                                 isActive: d["is_active"] as? Bool ?? false)
        }
        if list.map(\.id) != devices.map(\.id) {
            Log.info(.spotify, "Appareils : \(list.map { "\($0.name) (\($0.type))\($0.isActive ? " actif" : "")" })")
        }
        devices = list
        return list
    }

    // MARK: - Bibliothèque

    func loadLibrary() async {
        guard isConnected else { return }
        isLoadingLibrary = true
        defer { isLoadingLibrary = false }
        async let recent = api("GET", "/me/player/recently-played", query: ["limit": "20"])
        async let playlists = api("GET", "/me/playlists", query: ["limit": "30"])
        async let liked = api("GET", "/me/tracks", query: ["limit": "30"])
        let (r, p, l) = await (recent, playlists, liked)
        var out: [SpotifySection] = []
        if let items = Self.items(r.1, key: "items", unwrap: "track"), !items.isEmpty {
            // dédoublonnage des titres récents
            var seen = Set<String>()
            out.append(SpotifySection(id: "recent", title: "Écoutés récemment", items: items.filter { seen.insert($0.id).inserted }))
        }
        if let items = Self.items(p.1, key: "items", unwrap: nil), !items.isEmpty {
            out.append(SpotifySection(id: "playlists", title: "Tes playlists", items: items))
        }
        if let items = Self.items(l.1, key: "items", unwrap: "track"), !items.isEmpty {
            out.append(SpotifySection(id: "liked", title: "Titres likés", items: items))
        }
        sections = out
        lastLibraryLoad = Date()
        if let liked = out.first(where: { $0.id == "liked" }) {
            likedIDs = Set(liked.items.compactMap { $0.id.split(separator: ":").last.map(String.init) })
        }
        Log.info(.spotify, "Bibliothèque : \(out.map { "\($0.title) \($0.items.count)" }.joined(separator: ", "))")
    }

    /// Compat : plus de dossiers imbriqués avec l'API Web (playlist = lecture du contexte).
    func loadChildren(of uri: String) {}

    private static func items(_ data: Data?, key: String, unwrap: String?) -> [SpotifyItem]? {
        guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = json[key] as? [[String: Any]] else { return nil }
        return raw.compactMap { entry in
            let o = unwrap.flatMap { entry[$0] as? [String: Any] } ?? entry
            return item(from: o)
        }
    }

    private static func item(from o: [String: Any]) -> SpotifyItem? {
        guard let uri = o["uri"] as? String, let name = o["name"] as? String else { return nil }
        let type = o["type"] as? String ?? ""
        let artists = (o["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String }.joined(separator: ", ")
        let owner = (o["owner"] as? [String: Any])?["display_name"] as? String
        let label = ["track": "Titre", "album": "Album", "playlist": "Playlist", "artist": "Artiste"][type] ?? type.capitalized
        let images = (o["images"] as? [[String: Any]]) ?? ((o["album"] as? [String: Any])?["images"] as? [[String: Any]]) ?? []
        let url = (images.last?["url"] as? String ?? images.first?["url"] as? String).flatMap(URL.init(string:))
        return SpotifyItem(id: uri, title: name, subtitle: [label, artists ?? owner].compactMap { $0 }.joined(separator: " · "),
                           isContainer: type != "track", isPlayable: true, imageURL: url)
    }

    // MARK: - Recherche

    func search(_ query: String) async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, isConnected else { searchResults = []; return }
        isSearching = true
        defer { isSearching = false }
        let (_, data) = await api("GET", "/search", query: ["q": q, "type": "track,artist,album,playlist", "limit": "6"])
        guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        var out: [SpotifyItem] = []
        for key in ["tracks", "artists", "albums", "playlists"] {
            let raw = ((json[key] as? [String: Any])?["items"] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
            out += raw.compactMap(Self.item(from:))
        }
        searchResults = out
        Log.debug(.spotify, "Recherche « \(q) » : \(out.count) résultats")
    }

    // MARK: - Images

    func image(url: URL) async -> UIImage? {
        if let cached = imageCache.object(forKey: url as NSURL) { return cached }
        guard let (data, _) = try? await URLSession.shared.data(from: url), let raw = UIImage(data: data) else { return nil }
        // Décodage hors fil principal (sinon saccades de plusieurs centaines de ms)
        let img = await raw.byPreparingThumbnail(ofSize: CGSize(width: 320, height: 320)) ?? raw
        imageCache.setObject(img, forKey: url as NSURL)
        return img
    }

    // MARK: - Utilitaires

    private static func randomString(_ n: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<n).map { _ in chars.randomElement()! })
    }
}

extension SpotifyController: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
        }
    }
}

private extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

private extension String {
    var formEncoded: String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}

/// Stockage minimal dans le trousseau (refresh token Spotify).
enum Keychain {
    static func set(_ value: String, for key: String) {
        delete(key)
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key,
                                kSecValueData as String: Data(value.utf8),
                                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        SecItemAdd(q as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key]
        SecItemDelete(q as CFDictionary)
    }
}
