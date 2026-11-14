import AVFoundation
import Foundation

/// Personal sideload-only experiment, not an App Store background mode claim.
/// A short silent PCM file loops locally; it is mixed with Spotify and does not
/// set Now Playing information, request a microphone, or control Spotify playback.
@MainActor
final class BackgroundAudio {
    private var player: AVAudioPlayer?

    func start() throws {
        guard let url = Bundle.main.url(forResource: "silence", withExtension: "wav") else {
            throw CoroError.message("Falta un recurso de la app. Es necesario recompilar Coro.")
        }
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try audio.setActive(true)
        do {
            let localPlayer = try AVAudioPlayer(contentsOf: url)
            localPlayer.numberOfLoops = -1
            localPlayer.prepareToPlay()
            guard localPlayer.play() else { throw CoroError.message("iOS no permitió mantener la sesión activa.") }
            player = localPlayer
        } catch {
            try? audio.setActive(false, options: [.notifyOthersOnDeactivation])
            throw error
        }
    }

    func stop() {
        guard player != nil else { return }
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}
