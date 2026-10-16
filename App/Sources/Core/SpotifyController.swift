import Foundation
import Observation
import SpotifyiOS
import UIKit

/// Pilote l'app Spotify installée sur l'iPad via le SDK App Remote :
/// titre en cours, pochette, lecture/pause/suivant/précédent.
///
/// Prérequis : une app créée sur developer.spotify.com (Client ID) avec la redirect URI
/// `car3dui://spotify-login-callback`. Le Client ID se saisit dans Réglages › Logiciel
/// (ou via le réglage de build SPOTIFY_CLIENT_ID).
@MainActor
@Observable
final class SpotifyController: NSObject {
    static let redirectURL = URL(string: "car3dui://spotify-login-callback")!
    private static let clientIDKey = "SpotifyClientID"
    private static let tokenKey = "SpotifyAccessToken"

    var title = "Spotify"
    var artist = "Touchez pour connecter"
    var artwork: UIImage?
    var isPlaying = false
    var isConnected = false
    var duration: TimeInterval = 0
    var currentTime: TimeInterval = 0
    var recents: [UIImage] = []
    var lastError: String?

    var progress: Double { duration > 0 ? min(1, currentTime / duration) : 0 }

    var clientID: String {
        didSet {
            UserDefaults.standard.set(clientID, forKey: Self.clientIDKey)
            appRemote = nil
        }
    }

    var isConfigured: Bool { !clientID.trimmingCharacters(in: .whitespaces).isEmpty }

    @ObservationIgnored private var appRemote: SPTAppRemote?
    @ObservationIgnored private var lastTrackURI: String?
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

    private func remote() -> SPTAppRemote? {
        guard isConfigured else { return nil }
        if let appRemote { return appRemote }
        let config = SPTConfiguration(clientID: clientID, redirectURL: Self.redirectURL)
        let r = SPTAppRemote(configuration: config, logLevel: .error)
        r.connectionParameters.accessToken = UserDefaults.standard.string(forKey: Self.tokenKey)
        r.delegate = self
        appRemote = r
        return r
    }

    // MARK: - Connexion

    /// Ouvre Spotify pour autoriser l'app (et lancer la lecture), puis revient via `handle(url:)`.
    func authorize() {
        guard let r = remote() else {
            lastError = "Renseigne le Client ID Spotify dans Réglages › Logiciel."
            return
        }
        r.authorizeAndPlayURI("", completionHandler: nil)
    }

    /// Reconnexion silencieuse avec le jeton mémorisé (au retour au premier plan).
    func connect() {
        guard let r = remote(), r.connectionParameters.accessToken != nil, !r.isConnected else { return }
        r.connect()
    }

    func disconnect() {
        guard let r = appRemote, r.isConnected else { return }
        r.disconnect()
    }

    /// URL de retour de Spotify (`car3dui://spotify-login-callback#access_token=…`).
    func handle(url: URL) {
        guard url.scheme == Self.redirectURL.scheme, let r = remote() else { return }
        let params = r.authorizationParameters(from: url)
        if let token = params?[SPTAppRemoteAccessTokenKey] {
            UserDefaults.standard.set(token, forKey: Self.tokenKey)
            r.connectionParameters.accessToken = token
            r.connect()
        } else if let error = params?[SPTAppRemoteErrorDescriptionKey] {
            lastError = error
        }
    }

    // MARK: - Commandes

    func togglePlay() {
        guard let api = appRemote?.playerAPI, isConnected else { authorize(); return }
        if isPlaying { api.pause(nil) } else { api.resume(nil) }
    }

    func next() { appRemote?.playerAPI?.skip(toNext: nil) }
    func previous() { appRemote?.playerAPI?.skip(toPrevious: nil) }

    // MARK: - État

    private func apply(_ state: SPTAppRemotePlayerState) {
        let track = state.track
        title = track.name
        artist = track.artist.name
        isPlaying = !state.isPaused
        duration = TimeInterval(track.duration) / 1000
        currentTime = TimeInterval(state.playbackPosition) / 1000
        guard track.uri != lastTrackURI else { return }
        lastTrackURI = track.uri
        appRemote?.imageAPI?.fetchImage(forItem: track, with: CGSize(width: 300, height: 300)) { [weak self] result, _ in
            guard let image = result as? UIImage else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.artwork = image
                self.recents.insert(image, at: 0)
                self.recents = Array(self.recents.prefix(12))
            }
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
        }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        Task { @MainActor in
            isConnected = false
            lastError = error?.localizedDescription
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
