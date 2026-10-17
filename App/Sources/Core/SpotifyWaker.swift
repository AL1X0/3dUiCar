import Foundation
import SpotifyiOS
import UIKit

/// Réveil express de l'app Spotify quand elle dort (iOS l'endort après une longue pause) :
/// le SDK App Remote ouvre Spotify, lance directement l'élément demandé, puis Spotify revient
/// tout seul dans 3dUiCar via `car3dui://spotify-login-callback` (≈ 1 s, aucune action à faire).
/// C'est la seule façon autorisée par iOS de démarrer Spotify : une app ne peut pas le lancer
/// en arrière-plan, et aucune app tierce n'a le droit de jouer elle-même le son Spotify.
@MainActor
final class SpotifyWaker {
    private var remote: SPTAppRemote?
    private(set) var lastWake = Date.distantPast

    var isInstalled: Bool {
        URL(string: "spotify:").map { UIApplication.shared.canOpenURL($0) } ?? false
    }

    /// Ouvre Spotify sur `playURI` (playlist, album ou titre) avec retour automatique.
    func wake(clientID: String, playURI: String) {
        guard Date().timeIntervalSince(lastWake) > 4 else { return }   // anti double-tap
        lastWake = Date()
        let config = SPTConfiguration(clientID: clientID, redirectURL: URL(string: SpotifyController.redirectURI)!)
        let r = SPTAppRemote(configuration: config, logLevel: .error)
        remote = r
        Log.info(.spotify, "Réveil express de Spotify sur \(playURI.isEmpty ? "la dernière lecture" : playURI)")
        r.authorizeAndPlayURI(playURI, completionHandler: { ok in
            if !ok { Log.warning(.spotify, "Spotify n'a pas pu être réveillé (app installée ?)") }
        })
    }
}
