import AVFoundation
import MediaPlayer
import Observation
import SwiftUI

/// Volume système réel de l'iPad (pilote aussi le son de Spotify).
/// iOS n'expose pas de setter public : on passe par le curseur d'une MPVolumeView invisible.
@MainActor
@Observable
final class SystemVolume {
    private(set) var level: Float = AVAudioSession.sharedInstance().outputVolume

    @ObservationIgnored let volumeView = MPVolumeView(frame: CGRect(x: -200, y: -200, width: 10, height: 10))
    @ObservationIgnored private var observation: NSKeyValueObservation?

    init() {
        try? AVAudioSession.sharedInstance().setActive(true, options: [])
        observation = AVAudioSession.sharedInstance().observe(\.outputVolume) { [weak self] session, _ in
            let v = session.outputVolume
            Task { @MainActor in self?.level = v }
        }
    }

    func step(_ delta: Float) { set(level + delta) }

    func set(_ value: Float) {
        let v = max(0, min(1, value))
        level = v
        guard let slider = volumeView.subviews.compactMap({ $0 as? UISlider }).first else { return }
        slider.setValue(v, animated: false)
        slider.sendActions(for: .valueChanged)
    }

    var symbol: String {
        switch level {
        case 0: "speaker.slash.fill"
        case ..<0.34: "speaker.wave.1.fill"
        case ..<0.67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }
}

/// Héberge la MPVolumeView dans la hiérarchie (obligatoire pour que le curseur fonctionne).
struct VolumeHost: UIViewRepresentable {
    let volume: SystemVolume
    func makeUIView(context: Context) -> UIView {
        let v = UIView(frame: .zero)
        volume.volumeView.alpha = 0.01
        v.addSubview(volume.volumeView)
        return v
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
