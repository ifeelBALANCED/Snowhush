import AVFoundation

/// The generator heard outside while the snow falls: a loop played only while wanted and while the snow is, eased in and
/// out, and stopped once it has faded so that silence costs nothing.
final class GeneratorSound {
    /// Wanted from the menu.
    var enabled = false {
        didSet { update() }
    }
    /// Loudness, 0 to 1.
    var volume = 0.5 {
        didSet { update() }
    }
    /// The snow is on screen: false while the screens sleep or lock.
    var active = true {
        didSet { if active != oldValue { update() } }
    }

    private var player: AVAudioPlayer?
    private var stopping: DispatchWorkItem?

    private var playing: Bool { enabled && active && volume > 0 }

    private func update() {
        if playing {
            stopping?.cancel()
            stopping = nil
            start()
            player?.setVolume(Float(volume), fadeDuration: 0.6)
        } else if let player, player.isPlaying, stopping == nil {
            player.setVolume(0, fadeDuration: 0.6)
            let stop = DispatchWorkItem { [weak self] in
                guard let self else { return }
                stopping = nil
                if !playing { self.player?.stop(); self.player = nil }
            }
            stopping = stop
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: stop)
        }
    }

    private func start() {
        if player == nil {
            guard let url = Bundle.main.url(forResource: "generator", withExtension: "mp3", subdirectory: "Sounds"),
                  let made = try? AVAudioPlayer(contentsOf: url) else {
                NSLog("Snowhush: generator sound missing")
                return
            }
            made.numberOfLoops = -1
            made.volume = 0
            player = made
        }
        if player?.isPlaying == false { player?.play() }
    }
}
